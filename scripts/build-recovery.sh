#!/usr/bin/env bash
# Build the small authenticated initramfs used for whole-card cable updates.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${1:-${ROOT_DIR}/.build/buildroot-output/target}"
OUTPUT="${2:-${ROOT_DIR}/output/recovery.cpio.gz}"
[[ "${OUTPUT}" = /* ]] || OUTPUT="$(pwd)/${OUTPUT}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
[[ -x "${TARGET_DIR}/bin/busybox" ]] || die 'Buildroot BusyBox is unavailable'
[[ -x "${TARGET_DIR}/usr/sbin/dropbear" ]] || die 'Buildroot Dropbear is unavailable'
[[ -x "${TARGET_DIR}/usr/sbin/kexec" || -x "${TARGET_DIR}/sbin/kexec" ]] ||
    die 'Buildroot kexec is unavailable'

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT
root="${work}/root"
mkdir -p "${root}"/{bin,sbin,usr/sbin,etc,dev,proc,sys,root/.ssh,var/run,oldroot,lib}

cp "${TARGET_DIR}/bin/busybox" "${root}/bin/busybox"
cp "${TARGET_DIR}/usr/sbin/dropbear" "${root}/usr/sbin/dropbear"
cp "${ROOT_DIR}/scripts/recovery-init.sh" "${root}/init"
cp "${ROOT_DIR}/scripts/recovery-write.sh" "${root}/usr/sbin/rx1950-recovery-write"
chmod 0755 "${root}/init" "${root}/usr/sbin/rx1950-recovery-write"

# musl combines the dynamic loader and libc. Copy any additional direct shared
# dependencies reported by the target readelf, keeping recovery self-contained.
cp -L "${TARGET_DIR}/lib/ld-musl-arm.so.1" "${root}/lib/ld-musl-arm.so.1"
readelf="$(find "${TARGET_DIR}/../host/bin" -maxdepth 1 -name '*-readelf' -print -quit)"
[[ -x "${readelf}" ]] || die 'Buildroot target readelf is unavailable'
for binary in "${TARGET_DIR}/bin/busybox" "${TARGET_DIR}/usr/sbin/dropbear"; do
    while read -r library; do
        [[ "${library}" = 'libc.so' ]] && continue
        candidate="$(find "${TARGET_DIR}/lib" "${TARGET_DIR}/usr/lib" -name "${library}" -print -quit)"
        [[ -n "${candidate}" ]] || die "missing recovery dependency ${library}"
        cp -L "${candidate}" "${root}/lib/${library}"
    done < <("${readelf}" -d "${binary}" |
        sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p')
done

for applet in awk cat cp dd grep head id ip mkdir mount reboot setsid sh sha256sum sleep sync umount; do
    ln -s busybox "${root}/bin/${applet}"
done
ln -s ../../bin/busybox "${root}/usr/sbin/dropbearkey"
cat > "${root}/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/sh
EOF
cat > "${root}/etc/group" <<'EOF'
root:x:0:
EOF
cat > "${root}/etc/shadow" <<'EOF'
root:!:0:0:99999:7:::
EOF
: > "${root}/etc/rx1950-recovery"

mkdir -p "$(dirname "${OUTPUT}")"
(
    cd "${root}"
    find . -print0 | LC_ALL=C sort -z |
        cpio --null --create --format=newc --owner=0:0 --reproducible 2>/dev/null |
        gzip -n -9 > "${OUTPUT}"
)

kexec_source="${TARGET_DIR}/usr/sbin/kexec"
[[ -x "${kexec_source}" ]] || kexec_source="${TARGET_DIR}/sbin/kexec"
cp "${kexec_source}" "$(dirname "${OUTPUT}")/kexec"
chmod 0755 "$(dirname "${OUTPUT}")/kexec"
printf 'recovery initramfs: %s bytes\n' "$(stat -c '%s' "${OUTPUT}")"

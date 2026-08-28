#!/usr/bin/env bash
# Validate the rx1950 package-manager source contract, sealed rootfs config and
# generated opkg feed without executing target binaries on the CI host.
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly OPKG_CONF="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/opkg/opkg.conf"
readonly DEFCONFIG="${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
readonly FRAGMENT="${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_packages.fragment"
readonly FEED_URL="https://github.com/BlackF1re/rx1950-linux/releases/latest/download"
readonly FEED_ARCH="rx1950_armv4t_musl_v1"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
require_line() { grep -Fqx "$1" "$2" || die "$3"; }

validate_source() {
    require_line "src/gz rx1950 ${FEED_URL}" "${OPKG_CONF}" "rx1950 opkg feed URL missing"
    require_line "arch all 1" "${OPKG_CONF}" "opkg all architecture missing"
    require_line "arch ${FEED_ARCH} 100" "${OPKG_CONF}" "rx1950 opkg ABI architecture missing"
    require_line "dest root /" "${OPKG_CONF}" "opkg root destination missing"
    require_line "lists_dir ext /var/lib/opkg/lists" "${OPKG_CONF}" "opkg list directory missing"

    # opkg 0.7.0 enables HTTPS through libcurl only when libcurl is selected;
    # OpenSSL provides TLS and CA certificates provide server authentication.
    for requirement in \
        BR2_PACKAGE_OPKG=y \
        BR2_PACKAGE_LIBCURL=y \
        BR2_PACKAGE_LIBCURL_CURL=y \
        BR2_PACKAGE_LIBCURL_OPENSSL=y \
        BR2_PACKAGE_OPENSSL=y \
        BR2_PACKAGE_CA_CERTIFICATES=y; do
        require_line "${requirement}" "${DEFCONFIG}" "package-manager transport requirement missing: ${requirement}"
    done

    for requirement in \
        BR2_arm=y BR2_arm920t=y BR2_ARM_EABI=y BR2_SOFT_FLOAT=y \
        BR2_ARM_INSTRUCTIONS_ARM=y BR2_TOOLCHAIN_BUILDROOT_MUSL=y; do
        require_line "${requirement}" "${DEFCONFIG}" "rx1950 package ABI requirement missing: ${requirement}"
    done

    for package in BASH LESS NANO RSYNC TMUX TREE; do
        require_line "BR2_PACKAGE_${package}=y" "${FRAGMENT}" "initial feed package missing: ${package}"
    done

    grep -Fq 'base-show-info.json' "${ROOT_DIR}/scripts/build-opkg-feed.sh" || die "feed builder does not compare against the base package set"
    grep -Fq 'would overwrite base-image file' "${ROOT_DIR}/scripts/make-opkg-feed.py" || die "feed builder lacks base-file collision protection"
    grep -Fq 'rx1950_armv4t_musl_v1' "${ROOT_DIR}/scripts/make-opkg-feed.py" || die "feed builder ABI token mismatch"
}

validate_rootfs() {
    local rootfs="$1" extracted
    command -v debugfs >/dev/null 2>&1 || die "debugfs is required"
    [[ -s "${rootfs}" ]] || die "rootfs image is missing: ${rootfs}"
    extracted="$(mktemp)"
    trap 'rm -f "${extracted}"' RETURN
    debugfs -R 'dump /etc/opkg/opkg.conf '"${extracted}" "${rootfs}" >/dev/null 2>&1 || \
        die "sealed rootfs is missing /etc/opkg/opkg.conf"
    require_line "src/gz rx1950 ${FEED_URL}" "${extracted}" "sealed rootfs lost rx1950 package feed"
    require_line "arch ${FEED_ARCH} 100" "${extracted}" "sealed rootfs lost package ABI architecture"
    rm -f "${extracted}"
    trap - RETURN
}

validate_feed() {
    local dir="$1" package count=0
    [[ -s "${dir}/Packages" ]] || die "Packages index missing"
    [[ -s "${dir}/Packages.gz" ]] || die "Packages.gz missing"
    [[ -s "${dir}/feed.json" ]] || die "feed.json missing"
    [[ -s "${dir}/PACKAGES-SHA256SUMS" ]] || die "package checksums missing"
    gzip -t "${dir}/Packages.gz"
    (cd "${dir}" && sha256sum --check PACKAGES-SHA256SUMS)

    grep -Fq "Architecture: ${FEED_ARCH}" "${dir}/Packages" || die "feed architecture mismatch"
    grep -Fq '"epoch": 1' "${dir}/feed.json" || die "feed ABI epoch missing"

    for package in "${dir}"/*.ipk; do
        [[ -f "${package}" ]] || continue
        count=$((count + 1))
        mapfile -t members < <(ar t "${package}")
        [[ " ${members[*]} " == *' debian-binary '* ]] || die "$(basename "${package}") lacks debian-binary"
        [[ " ${members[*]} " == *' control.tar.gz '* ]] || die "$(basename "${package}") lacks control.tar.gz"
        [[ " ${members[*]} " == *' data.tar.gz '* ]] || die "$(basename "${package}") lacks data.tar.gz"
    done
    (( count > 0 )) || die "feed contains no ipk packages"

    python3 - "${dir}/Packages" <<'PY'
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
records = [r for r in text.strip().split("\n\n") if r.strip()]
names = set()
parsed = []
for record in records:
    fields = {}
    for line in record.splitlines():
        key, value = line.split(":", 1)
        fields[key] = value.strip()
    required = {"Package", "Version", "Architecture", "Filename", "SHA256sum"}
    missing = required - fields.keys()
    if missing:
        raise SystemExit(f"index record missing {sorted(missing)}")
    names.add(fields["Package"])
    parsed.append(fields)
for fields in parsed:
    for dep in filter(None, (v.strip() for v in fields.get("Depends", "").split(","))):
        dep = dep.split(" ", 1)[0]
        if dep not in names:
            raise SystemExit(f"{fields['Package']} has unresolved feed dependency {dep}")
PY
}

case "${1:-source}" in
    source) validate_source ;;
    rootfs)
        [[ "$#" -eq 2 ]] || die "usage: validate-opkg-feed.sh rootfs ROOTFS"
        validate_rootfs "$2"
        ;;
    feed)
        [[ "$#" -eq 2 ]] || die "usage: validate-opkg-feed.sh feed DIRECTORY"
        validate_feed "$2"
        ;;
    *) die "usage: validate-opkg-feed.sh {source|rootfs ROOTFS|feed DIRECTORY}" ;;
esac

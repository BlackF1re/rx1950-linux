#!/usr/bin/env bash
# Download a verified rx1950 image and flash it over the point-to-point USB link.

set -euo pipefail

# A non-login Git Bash started from PowerShell inherits Windows' OpenSSH ahead
# of the MSYS tools. Keep one coherent POSIX toolset (and its path handling)
# regardless of how the updater was launched.
case $(uname -s) in
    MINGW*|MSYS*)
        PATH="/usr/bin:/bin:${PATH}"; export PATH
        # Git for Windows 10.3 and Dropbear 2025.88 stall after exchanging
        # banners on this ARM target. Windows' in-box OpenSSH interoperates.
        ssh() { /c/WINDOWS/System32/OpenSSH/ssh.exe "$@"; }
        ;;
esac

REPOSITORY=BlackF1re/rx1950-linux
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE=192.168.7.2
BIND_ADDRESS=192.168.7.1
PASSWORD=${RX1950_PASSWORD-rx1950}
SOURCE=
VALUE=
ASSUME_YES=false

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'EOF'
usage: tools/update-rx1950.sh (--run ID | --release TAG | --latest | --dir PATH) [--yes]

  --run ID       install the assembled image artifact from a GitHub Actions run
  --release TAG  install a named GitHub release
  --latest       install the latest GitHub release
  --dir PATH     install an already downloaded payload directory
  --yes          skip the final destructive confirmation
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --run|--release|--dir)
            [[ $# -ge 2 && -z "${SOURCE}" ]] || die 'select exactly one image source'
            SOURCE=${1#--}; VALUE=$2; shift 2 ;;
        --latest)
            [[ -z "${SOURCE}" ]] || die 'select exactly one image source'
            SOURCE=latest; shift ;;
        --yes) ASSUME_YES=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown argument: $1" ;;
    esac
done
[[ -n "${SOURCE}" ]] || { usage >&2; exit 2; }

for command in gh plink pscp ssh ssh-keygen sha256sum xz awk; do
    command -v "${command}" >/dev/null || die "missing host command: ${command}"
done

temporary=$(mktemp -d)
trap 'rm -rf -- "${temporary}"' EXIT
payload=${temporary}/payload
mkdir -p "${payload}"

case "${SOURCE}" in
    run)
        artifact=$(gh api "repos/${REPOSITORY}/actions/runs/${VALUE}/artifacts" --paginate --jq \
            '.artifacts[] | select(.expired == false and (.name | startswith("rx1950-linux-"))) | .name' |
            head -n 1)
        [[ -n "${artifact}" ]] || die "run ${VALUE} has no assembled rx1950 image artifact"
        gh run download "${VALUE}" --repo "${REPOSITORY}" --name "${artifact}" --dir "${payload}"
        ;;
    release|latest)
        tag=${VALUE}
        [[ "${SOURCE}" = release ]] || tag=$(gh release view --repo "${REPOSITORY}" --json tagName --jq .tagName)
        gh release download "${tag}" --repo "${REPOSITORY}" --dir "${payload}" \
            --pattern '*.img.xz' --pattern SHA256SUMS --pattern zImage \
            --pattern recovery.cpio.gz
        ;;
    dir)
        payload=$(cd "${VALUE}" && pwd)
        ;;
esac

image=$(find "${payload}" -maxdepth 2 -type f -name 'rx1950-linux-*.img.xz' -print -quit)
checksums=$(find "${payload}" -maxdepth 2 -type f -name SHA256SUMS -print -quit)
kernel=$(find "${payload}" -maxdepth 2 -type f -name zImage -print -quit)
initramfs=$(find "${payload}" -maxdepth 2 -type f -name recovery.cpio.gz -print -quit)
recovery_startup=${ROOT_DIR}/board/hp_rx1950/startup-recovery.txt
[[ -s "${image}" && -s "${checksums}" && -s "${kernel}" && -s "${initramfs}" && -s "${recovery_startup}" ]] ||
    die 'payload is incomplete (image, checksums, kernel and recovery are required)'

image_name=$(basename "${image}")
raw_name=${image_name%.xz}
compressed_sha=$(awk -v name="${image_name}" '$2 == name { print $1 }' "${checksums}")
raw_sha=$(awk -v name="${raw_name}" '$2 == name { print $1 }' "${checksums}")
[[ "${compressed_sha}" =~ ^[0-9a-f]{64}$ && "${raw_sha}" =~ ^[0-9a-f]{64}$ ]] ||
    die 'SHA256SUMS does not describe both compressed and raw images'
printf '%s  %s\n' "${compressed_sha}" "${image}" | sha256sum --check --status ||
    die 'downloaded compressed image checksum mismatch'
raw_size=$(xz --robot --list "${image}" | awk -F '\t' '$1 == "totals" { print $5 }')
[[ "${raw_size}" =~ ^[0-9]+$ ]] || die 'cannot determine uncompressed image size'
initramfs_size=$(wc -c < "${initramfs}" | tr -d '[:space:]')
[[ "${initramfs_size}" =~ ^[1-9][0-9]*$ ]] || die 'cannot determine recovery initramfs size'

# HaRET relocates INITRD to RAMADDR + KERNEL_OFFSET + 0x508000.  Its
# ATAG_INITRD2 is not reliably consumed on this machine, while ATAG_CMDLINE is.
# Describe the same region explicitly so the kernel reserves and unpacks it.
generated_recovery_startup=${temporary}/startup-recovery.txt
awk -v size="${initramfs_size}" '
    /^set CMDLINE / {
        sub(/rdinit=\/init/, "initrd=0x31508000," size " rdinit=/init")
    }
    { print }
' "${recovery_startup}" > "${generated_recovery_startup}"
grep -Fq "initrd=0x31508000,${initramfs_size} rdinit=/init" "${generated_recovery_startup}" ||
    die 'failed to specialize the recovery HaRET command line'

key=${HOME}/.ssh/rx1950_update_ed25519
if [[ ! -s "${key}" || ! -s "${key}.pub" ]]; then
    mkdir -p "${HOME}/.ssh"
    ssh-keygen -q -t ed25519 -N '' -C 'rx1950 cable updater' -f "${key}"
fi

# Pin the key actually presented on the dedicated cable before using the
# factory engineering password to install our update-only transport key.
known_hosts=${temporary}/known_hosts
probe=$(plink -batch -ssh -pw "${PASSWORD}" root@"${DEVICE}" true 2>&1 || true)
fingerprint=$(printf '%s\n' "${probe}" | awk '/fingerprint is:/{getline; print $NF; exit}')
[[ "${fingerprint}" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]] ||
    die 'rx1950 SSH is not reachable over USB or its host key cannot be read'

# ssh-keyscan cannot negotiate the KEX selected by Dropbear 2025.88. Record a
# key with a credential-free normal handshake, then require it to match the
# independently reported PuTTY fingerprint before sending the password.
rm -f "${known_hosts}"
ssh -o BatchMode=yes -o PreferredAuthentications=none \
    -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="${known_hosts}" \
    -o ConnectTimeout=15 -o BindAddress="${BIND_ADDRESS}" \
    root@"${DEVICE}" true </dev/null >/dev/null 2>&1 || true
[[ -s "${known_hosts}" ]] || die 'cannot capture the rx1950 OpenSSH host key'
openssh_fingerprint=$(ssh-keygen -lf "${known_hosts}" -E sha256 | awk '{print $2}')
[[ "${openssh_fingerprint}" = "${fingerprint}" ]] || die 'SSH host-key probes disagree'
printf 'Cable device host key: %s\n' "${fingerprint}"

# Development images used "rx1950", while a freshly assembled image has the
# intentionally blank local root password. Try the configured/current value
# first, then the factory image value, so a successful update cannot lock out
# the next cable update. RX1950_PASSWORD overrides the first candidate.
device_password=
authenticated=false
for candidate in "${PASSWORD}" ''; do
    [[ "${authenticated}" = false ]] || break
    [[ -n "${device_password}" && "${candidate}" = "${device_password}" ]] && continue
    if plink -batch -ssh -hostkey "${fingerprint}" -pw "${candidate}" \
        root@"${DEVICE}" true >/dev/null 2>&1; then
        device_password=${candidate}
        authenticated=true
    fi
done
[[ "${authenticated}" = true ]] ||
    die 'neither the configured nor the fresh-image root password was accepted'

pscp -scp -batch -hostkey "${fingerprint}" -pw "${device_password}" "${key}.pub" \
    "root@${DEVICE}:/tmp/rx1950_update.pub" >/dev/null
plink -batch -hostkey "${fingerprint}" -pw "${device_password}" root@"${DEVICE}" \
    'mkdir -p /root/.ssh; chmod 700 /root/.ssh; touch /root/.ssh/authorized_keys; grep -qxF "$(cat /tmp/rx1950_update.pub)" /root/.ssh/authorized_keys || cat /tmp/rx1950_update.pub >> /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys; rm -f /tmp/rx1950_update.pub'

common_options=(-i "${key}" -o BatchMode=yes -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile="${known_hosts}" -o ConnectTimeout=5 \
    -o BindAddress="${BIND_ADDRESS}")
ssh_options=("${common_options[@]}")
remote=(root@"${DEVICE}")
plink_options=(-batch -ssh -hostkey "${fingerprint}" -pw "${device_password}")
pscp_options=(-scp -batch -hostkey "${fingerprint}" -pw "${device_password}")
plink "${plink_options[@]}" "${remote[0]}" \
    'test "$(cat /sys/class/power_supply/ac/online)" = 1' ||
    die 'external power is required for a whole-card update'

printf 'Verified payload: %s (%s bytes raw)\n' "${image_name}" "${raw_size}"
if ! ${ASSUME_YES}; then
    printf 'This will erase and replace the entire SD card in the rx1950. Type FLASH: '
    read -r confirmation
    [[ "${confirmation}" = FLASH ]] || die 'update cancelled'
fi

pscp "${pscp_options[@]}" "${kernel}" "${remote[0]}:/mnt/boot/zImage.ota"
pscp "${pscp_options[@]}" "${initramfs}" "${remote[0]}:/mnt/boot/recovery.cpio.gz"
pscp "${pscp_options[@]}" "${generated_recovery_startup}" "${remote[0]}:/mnt/boot/startup.update"

printf 'Entering authenticated RAM recovery through WM/HaRET...\n'
plink "${plink_options[@]}" "${remote[0]}" \
    'cp /mnt/boot/startup.txt /mnt/boot/startup.normal.txt && mv /mnt/boot/startup.update /mnt/boot/startup.txt && sync && reboot' || true
for _ in $(seq 1 120); do
    sleep 2
    if ssh "${ssh_options[@]}" "${remote[@]}" 'test -e /etc/rx1950-recovery' 2>/dev/null; then break; fi
done
ssh "${ssh_options[@]}" "${remote[@]}" 'test -e /etc/rx1950-recovery' ||
    die 'RAM recovery did not become reachable; its unattended fallback will reboot to the normal image'

printf 'Streaming and verifying the whole-card image...\n'
# Dropbear on this ARM9 needs a short pause between OpenSSH sessions; without
# it the next client can time out before the server banner is emitted.
sleep 10
xz --decompress --stdout "${image}" |
    ssh "${ssh_options[@]}" "${remote[@]}" "/usr/sbin/rx1950-recovery-write '${raw_size}' '${raw_sha}'" |
    tee "${temporary}/write.log"
grep -qx RX1950_UPDATE_VERIFIED "${temporary}/write.log" || die 'device did not confirm media verification'

ssh "${ssh_options[@]}" "${remote[@]}" 'sync; reboot -f' || true
printf 'Update verified. WM will now start HaRET automatically.\n'

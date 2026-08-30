#!/usr/bin/env bash
# Download a verified rx1950 image and flash it over the point-to-point USB link.

set -euo pipefail

REPOSITORY=BlackF1re/rx1950-linux
DEVICE=192.168.7.2
BIND_ADDRESS=192.168.7.1
PASSWORD=rx1950
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

for command in gh plink pscp ssh scp ssh-keygen ssh-keyscan sha256sum xz awk; do
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
            --pattern recovery.cpio.gz --pattern kexec
        ;;
    dir)
        payload=$(cd "${VALUE}" && pwd)
        ;;
esac

image=$(find "${payload}" -maxdepth 2 -type f -name 'rx1950-linux-*.img.xz' -print -quit)
checksums=$(find "${payload}" -maxdepth 2 -type f -name SHA256SUMS -print -quit)
kernel=$(find "${payload}" -maxdepth 2 -type f -name zImage -print -quit)
initramfs=$(find "${payload}" -maxdepth 2 -type f -name recovery.cpio.gz -print -quit)
kexec=$(find "${payload}" -maxdepth 2 -type f -name kexec -print -quit)
[[ -s "${image}" && -s "${checksums}" && -s "${kernel}" && -s "${initramfs}" && -s "${kexec}" ]] ||
    die 'payload is incomplete (image, checksums, kernel, recovery and kexec are required)'

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

key=${HOME}/.ssh/rx1950_update_ed25519
if [[ ! -s "${key}" || ! -s "${key}.pub" ]]; then
    mkdir -p "${HOME}/.ssh"
    ssh-keygen -q -t ed25519 -N '' -C 'rx1950 cable updater' -f "${key}"
fi

# Pin the key actually presented on the dedicated cable before using the
# factory engineering password to install our update-only transport key.
known_hosts=${temporary}/known_hosts
for _ in $(seq 1 30); do
    ssh-keyscan -T 2 -t ed25519 "${DEVICE}" >"${known_hosts}" 2>/dev/null && break
    sleep 2
done
[[ -s "${known_hosts}" ]] || die 'rx1950 SSH is not reachable over USB'
fingerprint=$(ssh-keygen -lf "${known_hosts}" -E sha256 | awk '{print $2}')
printf 'Cable device host key: %s\n' "${fingerprint}"
pscp -batch -hostkey "${fingerprint}" -pw "${PASSWORD}" "${key}.pub" \
    "root@${DEVICE}:/tmp/rx1950_update.pub" >/dev/null
plink -batch -hostkey "${fingerprint}" -pw "${PASSWORD}" root@"${DEVICE}" \
    'mkdir -p /root/.ssh; chmod 700 /root/.ssh; touch /root/.ssh/authorized_keys; grep -qxF "$(cat /tmp/rx1950_update.pub)" /root/.ssh/authorized_keys || cat /tmp/rx1950_update.pub >> /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys; rm -f /tmp/rx1950_update.pub'

ssh_options=(-i "${key}" -o BatchMode=yes -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile="${known_hosts}" -o ConnectTimeout=5 -b "${BIND_ADDRESS}")
remote=(root@"${DEVICE}")
ssh "${ssh_options[@]}" "${remote[@]}" 'test "$(cat /sys/class/power_supply/ac/online)" = 1' ||
    die 'external power is required for a whole-card update'

printf 'Verified payload: %s (%s bytes raw)\n' "${image_name}" "${raw_size}"
if ! ${ASSUME_YES}; then
    printf 'This will erase and replace the entire SD card in the rx1950. Type FLASH: '
    read -r confirmation
    [[ "${confirmation}" = FLASH ]] || die 'update cancelled'
fi

scp "${ssh_options[@]}" "${kernel}" "${remote[0]}:/mnt/boot/zImage.ota"
scp "${ssh_options[@]}" "${initramfs}" "${remote[0]}:/mnt/boot/recovery.cpio.gz"
scp "${ssh_options[@]}" "${kexec}" "${remote[0]}:/tmp/kexec"
ssh "${ssh_options[@]}" "${remote[@]}" 'chmod 755 /tmp/kexec; sync'

# Images installed before OTA support need one normal HaRET cycle to start a
# kernel containing kexec. The WM Startup shortcut handles that cycle.
if ! ssh "${ssh_options[@]}" "${remote[@]}" 'test -e /sys/kernel/kexec_loaded'; then
    printf 'Bootstrapping the OTA-capable kernel through WM/HaRET...\n'
    ssh "${ssh_options[@]}" "${remote[@]}" \
        'cp /mnt/boot/zImage /mnt/boot/zImage.previous; mv /mnt/boot/zImage.ota /mnt/boot/zImage; sync; reboot' || true
    for _ in $(seq 1 90); do
        sleep 2
        if ssh "${ssh_options[@]}" "${remote[@]}" 'test -e /sys/kernel/kexec_loaded' 2>/dev/null; then break; fi
    done
    ssh "${ssh_options[@]}" "${remote[@]}" 'test -e /sys/kernel/kexec_loaded' ||
        die 'OTA kernel did not return; start HaRET manually or restore zImage.previous'
    scp "${ssh_options[@]}" "${kernel}" "${remote[0]}:/mnt/boot/zImage.ota"
    scp "${ssh_options[@]}" "${kexec}" "${remote[0]}:/tmp/kexec"
    ssh "${ssh_options[@]}" "${remote[@]}" 'chmod 755 /tmp/kexec'
fi

printf 'Entering authenticated RAM recovery...\n'
ssh "${ssh_options[@]}" "${remote[@]}" \
    "/tmp/kexec -l /mnt/boot/zImage.ota --type=zImage --initrd=/mnt/boot/recovery.cpio.gz --append='rdinit=/init console=tty0 loglevel=4 consoleblank=0' && sync && /tmp/kexec -e" || true
for _ in $(seq 1 60); do
    sleep 2
    if ssh "${ssh_options[@]}" "${remote[@]}" 'test -e /etc/rx1950-recovery' 2>/dev/null; then break; fi
done
ssh "${ssh_options[@]}" "${remote[@]}" 'test -e /etc/rx1950-recovery' ||
    die 'RAM recovery did not become reachable'

printf 'Streaming and verifying the whole-card image...\n'
xz --decompress --stdout "${image}" |
    ssh "${ssh_options[@]}" "${remote[@]}" "/usr/sbin/rx1950-recovery-write '${raw_size}' '${raw_sha}'" |
    tee "${temporary}/write.log"
grep -qx RX1950_UPDATE_VERIFIED "${temporary}/write.log" || die 'device did not confirm media verification'

ssh "${ssh_options[@]}" "${remote[@]}" 'sync; reboot -f' || true
printf 'Update verified. WM will now start HaRET automatically.\n'

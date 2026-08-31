#!/usr/bin/env bash
# Download a verified rx1950 image and flash it over the point-to-point USB link.

set -euo pipefail

# A non-login Git Bash started from PowerShell inherits Windows' OpenSSH ahead
# of the MSYS tools. Keep one coherent POSIX toolset (and its path handling)
# regardless of how the updater was launched.
case $(uname -s) in
    MINGW*|MSYS*)
        PATH="/usr/bin:/bin:${PATH}"; export PATH
        # Use PuTTY tools consistently. The Windows OpenSSH client can time
        # out while waiting for a Dropbear banner on this ARM target.
        ;;
esac

REPOSITORY=BlackF1re/rx1950-linux
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE=192.168.7.2
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

for command in gh plink pscp sha256sum xz awk; do
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
            --pattern '*.img.xz' --pattern SHA256SUMS --pattern zImage-recovery
        ;;
    dir)
        payload=$(cd "${VALUE}" && pwd)
        ;;
esac

image=$(find "${payload}" -maxdepth 2 -type f -name 'rx1950-linux-*.img.xz' -print -quit)
checksums=$(find "${payload}" -maxdepth 2 -type f -name SHA256SUMS -print -quit)
recovery_kernel=$(find "${payload}" -maxdepth 2 -type f -name zImage-recovery -print -quit)
recovery_startup=${ROOT_DIR}/board/hp_rx1950/startup-recovery.txt
[[ -s "${image}" && -s "${checksums}" && -s "${recovery_kernel}" && -s "${recovery_startup}" ]] ||
    die 'payload is incomplete (image, checksums and embedded recovery kernel are required)'

image_name=$(basename "${image}")
raw_name=${image_name%.xz}
compressed_sha=$(awk -v name="${image_name}" '$2 == name { print $1 }' "${checksums}")
raw_sha=$(awk -v name="${raw_name}" '$2 == name { print $1 }' "${checksums}")
recovery_sha=$(awk '$2 == "zImage-recovery" { print $1 }' "${checksums}")
[[ "${compressed_sha}" =~ ^[0-9a-f]{64}$ && "${raw_sha}" =~ ^[0-9a-f]{64}$ &&
   "${recovery_sha}" =~ ^[0-9a-f]{64}$ ]] ||
    die 'SHA256SUMS does not describe compressed/raw images and recovery kernel'
printf '%s  %s\n' "${compressed_sha}" "${image}" | sha256sum --check --status ||
    die 'downloaded compressed image checksum mismatch'
printf '%s  %s\n' "${recovery_sha}" "${recovery_kernel}" | sha256sum --check --status ||
    die 'downloaded recovery kernel checksum mismatch'
raw_size=$(xz --robot --list "${image}" | awk -F '\t' '$1 == "totals" { print $5 }')
[[ "${raw_size}" =~ ^[0-9]+$ ]] || die 'cannot determine uncompressed image size'
# Both normal Linux and RAM recovery are deliberately open only through the
# point-to-point USB cable. The SSH host key is pinned for each short session,
# but no user password or client key exists in this appliance workflow.
probe=$(plink -batch -ssh -pw '' root@"${DEVICE}" true 2>&1 || true)
fingerprint=$(printf '%s\n' "${probe}" | awk '/fingerprint is:/{getline; print $NF; exit}')
[[ "${fingerprint}" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]] ||
    die 'rx1950 SSH is not reachable over USB or its host key cannot be read'

printf 'Cable device host key: %s\n' "${fingerprint}"

remote=(root@"${DEVICE}")
normal_options=(-batch -ssh -hostkey "${fingerprint}" -pw '')
normal_scp_options=(-scp -batch -hostkey "${fingerprint}" -pw '')
plink "${normal_options[@]}" "${remote[0]}" \
    'test "$(cat /sys/class/power_supply/ac/online)" = 1' ||
    die 'external power is required for a whole-card update'

printf 'Verified payload: %s (%s bytes raw)\n' "${image_name}" "${raw_size}"
if ! ${ASSUME_YES}; then
    printf 'This will erase and replace the entire SD card in the rx1950. Type FLASH: '
    read -r confirmation
    [[ "${confirmation}" = FLASH ]] || die 'update cancelled'
fi

pscp "${normal_scp_options[@]}" "${recovery_kernel}" "${remote[0]}:/mnt/boot/zImage.ota"
pscp "${normal_scp_options[@]}" "${recovery_startup}" "${remote[0]}:/mnt/boot/startup.update"

printf 'Entering passwordless RAM recovery through WM/HaRET...\n'
plink "${normal_options[@]}" "${remote[0]}" \
    'cp /mnt/boot/startup.txt /mnt/boot/startup.normal.txt && mv /mnt/boot/startup.update /mnt/boot/startup.txt && sync && reboot' || true
recovery_fingerprint=
for _ in $(seq 1 120); do
    sleep 2
    recovery_probe=$(plink -batch -ssh -pw '' "${remote[0]}" true 2>&1 || true)
    recovery_fingerprint=$(printf '%s\n' "${recovery_probe}" | awk '/fingerprint is:/{getline; print $NF; exit}')
    [[ "${recovery_fingerprint}" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]] || continue
    recovery_options=(-batch -ssh -hostkey "${recovery_fingerprint}" -pw '')
    if plink "${recovery_options[@]}" "${remote[0]}" 'test -e /etc/rx1950-recovery' 2>/dev/null; then break; fi
done
[[ -n "${recovery_fingerprint}" ]] || die 'RAM recovery did not expose an SSH host key'
plink "${recovery_options[@]}" "${remote[0]}" 'test -e /etc/rx1950-recovery' ||
    die 'RAM recovery did not become reachable; its unattended fallback will reboot to the normal image'

printf 'Streaming and verifying the whole-card image...\n'
# Dropbear on this ARM9 needs a short pause between sessions; without it the
# next client can time out before the server banner is emitted.
sleep 10
xz --decompress --stdout "${image}" |
    plink "${recovery_options[@]}" "${remote[0]}" "/usr/sbin/rx1950-recovery-write '${raw_size}' '${raw_sha}'" |
    tee "${temporary}/write.log"
grep -qx RX1950_UPDATE_VERIFIED "${temporary}/write.log" || die 'device did not confirm media verification'

plink "${recovery_options[@]}" "${remote[0]}" 'sync; reboot -f' || true
printf 'Update verified. WM will now start HaRET automatically.\n'

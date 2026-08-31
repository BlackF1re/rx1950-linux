#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

readonly ROOT_DIR="${RX1950_CACHE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=sources.lock.sh
source "${ROOT_DIR}/scripts/sources.lock.sh"

canonical_kconfig() {
    sed -e 's/\r$//' "$1" |
        grep -E '^[A-Z0-9_]+=|^# [A-Z0-9_]+ is not set$' |
        LC_ALL=C sort
}

canonical_build_file() {
    sed -e 's/\r$//' -e 's/[[:space:]]\+$//' "$1" |
        grep -Ev '^[[:space:]]*(#|$)'
}

canonical_patch() {
    # Patch mail headers and signatures do not affect the built payload. Hash
    # the complete diff (including modes and rename metadata), but stop at the
    # standard mail-patch signature separator.
    sed -e 's/\r$//' "$1" | awk '
        /^diff --git / { in_diff=1 }
        in_diff && $0 == "-- " { exit }
        in_diff { print }
    '
}

case "${1:-}" in
    rootfs)
        {
            printf 'buildroot=%s\n' "${BUILDROOT_VERSION}"
            canonical_kconfig "${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
            canonical_kconfig "${ROOT_DIR}/buildroot/external/rx1950/configs/busybox.fragment"
            canonical_build_file "${ROOT_DIR}/buildroot/external/rx1950/Config.in"
            canonical_build_file "${ROOT_DIR}/buildroot/external/rx1950/external.mk"
            while IFS= read -r package_file; do
                printf 'package=%s\n' "${package_file#"${ROOT_DIR}/"}"
                canonical_build_file "${package_file}"
            done < <(find "${ROOT_DIR}/buildroot/external/rx1950/package" -type f \
                \( -name 'Config.in' -o -name '*.mk' -o -name '*.hash' \) \
                -print | LC_ALL=C sort)
            if [[ -d "${ROOT_DIR}/buildroot/external/rx1950/patches" ]]; then
                while IFS= read -r patch_file; do
                    printf 'patch=%s\n' "${patch_file#"${ROOT_DIR}/"}"
                    canonical_patch "${patch_file}"
                done < <(find "${ROOT_DIR}/buildroot/external/rx1950/patches" \
                    -type f -name '*.patch' -print | LC_ALL=C sort)
            fi
        } | sha256sum | cut -d' ' -f1
        ;;
    *)
        printf 'usage: %s rootfs\n' "$0" >&2
        exit 2
        ;;
esac

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

case "${1:-}" in
    rootfs)
        {
            printf 'buildroot=%s\n' "${BUILDROOT_VERSION}"
            canonical_kconfig "${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
            canonical_kconfig "${ROOT_DIR}/buildroot/external/rx1950/configs/busybox.fragment"
            canonical_build_file "${ROOT_DIR}/buildroot/external/rx1950/Config.in"
            canonical_build_file "${ROOT_DIR}/buildroot/external/rx1950/external.mk"
        } | sha256sum | cut -d' ' -f1
        ;;
    *)
        printf 'usage: %s rootfs\n' "$0" >&2
        exit 2
        ;;
esac

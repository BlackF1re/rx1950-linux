#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOTFS="${1:-${ROOT_DIR}/output/rootfs.ext2}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
command -v debugfs >/dev/null 2>&1 || die 'debugfs is required for rootfs payload validation'
test -s "${ROOTFS}" || die "rootfs image is missing: ${ROOTFS}"

has() {
    debugfs -R "stat $1" "${ROOTFS}" 2>&1 | grep -q 'Inode:'
}

for path in \
    /usr/sbin/iw \
    /usr/bin/kmod \
    /sbin/modprobe \
    /usr/sbin/wpa_supplicant \
    /usr/sbin/wpa_passphrase \
    /usr/sbin/rx1950-wlan \
    /usr/sbin/rx1950-wlan-firmware \
    /usr/sbin/rx1950-blue \
    /etc/opkg/opkg.conf \
    /etc/opkg/distfeeds.conf \
    /etc/init.d/S10kernel-modules \
    /etc/init.d/S40wlan; do
    has "$path" || die "rootfs payload is missing ${path}"
done

# Proprietary TI firmware must be installed/imported by the owner of the
# handheld and must never leak into our redistributable image.
if has /lib/firmware/WLANGEN.BIN; then
    die 'rootfs payload illegally contains proprietary WLANGEN.BIN'
fi

printf 'rootfs WLAN/package-manager payload: OK\n'

#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOTFS="${1:-${ROOT_DIR}/output/rootfs.ext2}"
readonly MAIN_SHA256="3d92318dadef22b1d1b062925ef66bac2ad48a0fd4fc83b88dcabba38c182b7b"
readonly RADIO0D_SHA256="ee75c05bb8a17a7978abbbc0f38fb79b1915c1e2357889e65657a39024d5b3a3"
readonly RADIO11_SHA256="e005a93a0b463e01edba2b79038b54c29a7932efee61c851a2ac644b8a4e5dd4"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
command -v debugfs >/dev/null 2>&1 || die 'debugfs is required for rootfs payload validation'
command -v sha256sum >/dev/null 2>&1 || die 'sha256sum is required for rootfs payload validation'
test -s "${ROOTFS}" || die "rootfs image is missing: ${ROOTFS}"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

has() {
    debugfs -R "stat $1" "${ROOTFS}" 2>&1 | grep -q 'Inode:'
}

extract() {
    local source="$1" destination="$2"
    debugfs -R "dump -p ${source} ${destination}" "${ROOTFS}" >/dev/null 2>&1 ||
        die "cannot extract ${source}"
}

for path in \
    /usr/sbin/iw \
    /usr/bin/kmod \
    /sbin/modprobe \
    /usr/sbin/wpa_supplicant \
    /usr/sbin/wpa_passphrase \
    /usr/bin/curl \
    /etc/ssl/certs/ca-certificates.crt \
    /usr/share/zoneinfo/Etc/UTC \
    /usr/sbin/ntpd \
    /usr/sbin/rx1950-time-sync \
    /usr/sbin/rx1950-timezone \
    /usr/sbin/rx1950-wlan \
    /usr/sbin/rx1950-wlan-firmware \
    /usr/sbin/rx1950-blue \
    /usr/share/udhcpc/rx1950-usb.script \
    /etc/default/dropbear \
    /etc/opkg/opkg.conf \
    /etc/opkg/distfeeds.conf \
    /etc/init.d/S10kernel-modules \
    /etc/init.d/S35usb-gadget \
    /etc/init.d/S38time-sync \
    /etc/init.d/S40wlan \
    /lib/firmware/WLANGEN.BIN \
    /lib/firmware/RADIO0d.BIN \
    /lib/firmware/RADIO11.BIN; do
    has "$path" || die "rootfs payload is missing ${path}"
done

extract /lib/firmware/WLANGEN.BIN "${tmp}/WLANGEN.BIN"
extract /lib/firmware/RADIO0d.BIN "${tmp}/RADIO0d.BIN"
extract /lib/firmware/RADIO11.BIN "${tmp}/RADIO11.BIN"
printf '%s  %s\n' "$MAIN_SHA256" "${tmp}/WLANGEN.BIN" | sha256sum --check --status ||
    die 'bundled WLANGEN.BIN checksum mismatch'
printf '%s  %s\n' "$RADIO0D_SHA256" "${tmp}/RADIO0d.BIN" | sha256sum --check --status ||
    die 'bundled RADIO0d.BIN checksum mismatch'
printf '%s  %s\n' "$RADIO11_SHA256" "${tmp}/RADIO11.BIN" | sha256sum --check --status ||
    die 'bundled RADIO11.BIN checksum mismatch'

extract /etc/shadow "${tmp}/shadow"
grep -q '^root::' "${tmp}/shadow" || die 'root account is not configured with a blank password'
extract /etc/default/dropbear "${tmp}/dropbear"
grep -Eq '^DROPBEAR_ARGS="[^"]*-B[^"]*"$' "${tmp}/dropbear" ||
    die 'Dropbear does not allow the intentionally blank local root password'

extract /etc/init.d/S35usb-gadget "${tmp}/S35usb-gadget"
grep -Fq 'udhcpc -f -i usb0' "${tmp}/S35usb-gadget" ||
    die 'USB DHCP client is not persistent'
extract /etc/init.d/S38time-sync "${tmp}/S38time-sync"
grep -Fq 'rx1950-time-sync' "${tmp}/S38time-sync" ||
    die 'boot-time NTP synchronization is not enabled'

printf 'rootfs WLAN/USB/HTTPS/time/login payload: OK\n'

#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOTFS="${1:-${ROOT_DIR}/output/rootfs.ext2}"
readonly MAIN_SHA256="4f05913c940c2455b267545b12d93ad81fa5eebb0cbee22a2c7588c50525b4f0"
readonly RADIO0D_SHA256="6a4a7fbb24a328a88261bc2a507b2a0bf63c91e831e3f1a8caa4f6599b2215e6"
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
    /etc/init.d/S20zram \
    /etc/init.d/S35usb-gadget \
    /etc/init.d/S38time-sync \
    /etc/init.d/S40wlan \
    /etc/init.d/S48xserver \
    /etc/init.d/S50matchbox \
    /usr/bin/Xorg \
    /usr/lib/xorg/modules/libshadow.so \
    /usr/lib/xorg/modules/libfbdevhw.so \
    /usr/lib/xorg/modules/drivers/fbdev_drv.so \
    /usr/lib/xorg/modules/input/evdev_drv.so \
    /etc/X11/xorg.conf \
    /lib/firmware/regulatory.db \
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

extract /etc/init.d/S20zram "${tmp}/S20zram"
grep -Fq 'lzo-rle' "${tmp}/S20zram" || die 'zram compressor is not lzo-rle'
extract /etc/init.d/S48xserver "${tmp}/S48xserver"
grep -Fq 'Xorg :0' "${tmp}/S48xserver" || die 'Xorg is not started at boot'
extract /etc/X11/xorg.conf "${tmp}/xorg.conf"
for module in fb shadow fbdevhw; do
    grep -Eq "^[[:space:]]*Load[[:space:]]+\"${module}\"" "${tmp}/xorg.conf" ||
        die "Xorg does not preload the ${module} module required by fbdev on musl"
done

printf 'rootfs WLAN/USB/GUI/zram/regulatory payload: OK\n'

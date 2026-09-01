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
command -v readelf >/dev/null 2>&1 || die 'readelf is required for Xorg dependency validation'
test -s "$ROOTFS" || die "rootfs image is missing: $ROOTFS"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

has() { debugfs -R "stat $1" "$ROOTFS" 2>&1 | grep -q 'Inode:'; }
extract() {
    local source="$1" destination="$2"
    debugfs -R "dump -p ${source} ${destination}" "$ROOTFS" >/dev/null 2>&1 || die "cannot extract ${source}"
}
require_path() { has "$1" || die "rootfs payload is missing $1"; }
forbid_path() { ! has "$1" || die "obsolete/unwanted rootfs payload remains: $1"; }

for path in \
    /usr/sbin/iw /usr/bin/kmod /sbin/modprobe \
    /usr/sbin/wpa_supplicant /usr/sbin/wpa_passphrase /usr/bin/curl \
    /etc/ssl/certs/ca-certificates.crt /usr/share/zoneinfo/Etc/UTC /usr/sbin/ntpd \
    /usr/sbin/rx1950-time-sync /usr/sbin/rx1950-usb-dhcp /usr/sbin/rx1950-timezone \
    /usr/sbin/rx1950-wlan /usr/sbin/rx1950-wlan-firmware /usr/sbin/rx1950-xorg-config \
    /usr/sbin/rx1950-control /usr/sbin/rx1950-battery /usr/sbin/rx1950-sensors \
    /usr/bin/rx1950-keyboard /usr/bin/rx1950-launch /usr/bin/rx1950-jwm-app-menu \
    /usr/bin/rx1950-jwm-panel-config /usr/bin/mb-applet-xterm-wrapper.sh \
    /usr/bin/rx1950-settings /usr/bin/jwm /usr/bin/matchbox-keyboard \
    /usr/bin/pcmanfm /usr/bin/leafpad /usr/bin/dillo /usr/bin/xterm /usr/bin/xcalc /usr/bin/xset \
    /usr/sbin/thd /usr/bin/Xorg /usr/bin/xinput /usr/bin/xinput_calibrator \
    /usr/bin/amixer /usr/bin/arecord /usr/sbin/alsactl /usr/bin/speaker-test \
    /usr/lib/xorg/modules/libshadow.so /usr/lib/xorg/modules/libfbdevhw.so \
    /usr/lib/xorg/modules/drivers/fbdev_drv.so /usr/lib/xorg/modules/input/evdev_drv.so \
    /etc/default/rx1950-input /etc/default/rx1950-ui /etc/default/rx1950-keyboard \
    /etc/default/rx1950-wlan /etc/default/rx1950-buttons /etc/default/rx1950-power \
    /etc/default/triggerhappy /etc/default/dropbear \
    /etc/jwm/system.jwmrc /etc/jwm/theme /etc/triggerhappy/triggers.d/rx1950.conf \
    /usr/share/applications/rx1950-files.desktop /usr/share/applications/rx1950-editor.desktop \
    /usr/share/applications/rx1950-browser.desktop /usr/share/applications/rx1950-terminal.desktop \
    /usr/share/applications/rx1950-settings.desktop /usr/share/applications/rx1950-wifi.desktop \
    /etc/opkg/opkg.conf /etc/opkg/distfeeds.conf \
    /etc/init.d/S20zram /etc/init.d/S30alsa /etc/init.d/S35usb-gadget \
    /etc/init.d/S38time-sync /etc/init.d/S40wlan /etc/init.d/S48xserver /etc/init.d/S50jwm \
    /lib/firmware/regulatory.db /lib/firmware/regulatory.db.p7s \
    /lib/firmware/WLANGEN.BIN /lib/firmware/RADIO0d.BIN /lib/firmware/RADIO11.BIN; do
    require_path "$path"
done

for path in \
    /etc/init.d/S10udev /etc/init.d/S40xorg /etc/X11/xorg.conf \
    /usr/bin/dialog /usr/bin/xedit \
    /usr/sbin/rx1950-wifi-ui /usr/sbin/rx1950-jwm-status-menu \
    /usr/sbin/rx1950-power-menu /usr/sbin/rx1950-button-settings \
    /usr/bin/rx1950-wifi-launcher; do
    forbid_path "$path"
done

# Verified, self-contained ACX100 firmware.
extract /lib/firmware/WLANGEN.BIN "$tmp/WLANGEN.BIN"
extract /lib/firmware/RADIO0d.BIN "$tmp/RADIO0d.BIN"
extract /lib/firmware/RADIO11.BIN "$tmp/RADIO11.BIN"
printf '%s  %s\n' "$MAIN_SHA256" "$tmp/WLANGEN.BIN" | sha256sum --check --status || die 'bundled WLANGEN.BIN checksum mismatch'
printf '%s  %s\n' "$RADIO0D_SHA256" "$tmp/RADIO0d.BIN" | sha256sum --check --status || die 'bundled RADIO0d.BIN checksum mismatch'
printf '%s  %s\n' "$RADIO11_SHA256" "$tmp/RADIO11.BIN" | sha256sum --check --status || die 'bundled RADIO11.BIN checksum mismatch'

# Existing local-console/recovery access contract.
extract /etc/shadow "$tmp/shadow"
grep -q '^root::' "$tmp/shadow" || die 'root account is not configured with a blank password'
extract /etc/default/dropbear "$tmp/dropbear"
grep -Eq '^DROPBEAR_ARGS="[^"]*-B[^"]*"$' "$tmp/dropbear" || die 'Dropbear does not allow the intentionally blank local root password'

# Resident-memory and startup policy.
extract /etc/init.d/S20zram "$tmp/S20zram"
grep -Fq 'echo 12M > /sys/block/zram0/disksize' "$tmp/S20zram" || die 'zram size is not bounded to 12 MiB'
grep -Fq 'lzo-rle' "$tmp/S20zram" || die 'zram compressor is not lzo-rle'
extract /etc/init.d/S48xserver "$tmp/S48xserver"
grep -Fq 'rx1950-xorg-config "$CONFIG"' "$tmp/S48xserver" || die 'Xorg does not use runtime hardware discovery'
grep -Fq -- '-nolisten tcp' "$tmp/S48xserver" || die 'Xorg TCP listener is enabled'
grep -Fq -- '-dpi "$DPI"' "$tmp/S48xserver" || die 'Xorg does not apply configurable global DPI'
extract /usr/bin/Xorg "$tmp/Xorg"
readelf -d "$tmp/Xorg" | grep -q 'Shared library: \[libcrypto' && die 'resident Xorg still links libcrypto'
readelf -d "$tmp/Xorg" | grep -q 'Shared library: \[libsha1' || die 'resident Xorg is not using compact libsha1'

# Dynamic X/input contract: no fixed eventN path, no resident udev dependency.
extract /usr/sbin/rx1950-xorg-config "$tmp/rx1950-xorg-config"
grep -Fq '/sys/class/input/event*' "$tmp/rx1950-xorg-config" || die 'input devices are not discovered from sysfs'
grep -Fq 'Option "AutoAddDevices" "false"' "$tmp/rx1950-xorg-config" || die 'Xorg relies on udev hotplug'
grep -Fq 'TOUCH_CALIBRATION' "$tmp/rx1950-xorg-config" || die 'persistent touch calibration support missing'
! grep -Eq '/dev/input/event[0-9]+' "$tmp/rx1950-xorg-config" || die 'hard-coded input event path remains'

# JWM/desktop contract: user-owned config, generated panel, XDG application menu.
extract /etc/init.d/S50jwm "$tmp/S50jwm"
grep -Fq 'jwm -f "$JWMRC"' "$tmp/S50jwm" || die 'JWM does not use the user-owned config'
grep -Fq 'rx1950-jwm-panel-config' "$tmp/S50jwm" || die 'managed panel config is not generated'
! grep -Eq '^[[:space:]]*(rx1950-keyboard|matchbox-keyboard)([[:space:]]+show)?[[:space:]]*&' "$tmp/S50jwm" || die 'on-screen keyboard starts unconditionally'
extract /etc/jwm/system.jwmrc "$tmp/system.jwmrc"
grep -Fq '<Dynamic label="Applications">exec:/usr/bin/rx1950-jwm-app-menu</Dynamic>' "$tmp/system.jwmrc" || die 'application menu is not generated from XDG metadata'
grep -Fq '<Include>/root/.config/jwm/panel</Include>' "$tmp/system.jwmrc" || die 'JWM panel is not configurable data'
grep -Fq '<Include>/root/.config/jwm/theme</Include>' "$tmp/system.jwmrc" || die 'JWM theme is not user-owned'
extract /usr/bin/rx1950-jwm-app-menu "$tmp/rx1950-jwm-app-menu"
grep -Fq '/usr/share/applications' "$tmp/rx1950-jwm-app-menu" || die 'system .desktop applications are not discovered'
grep -Fq '.local/share/applications' "$tmp/rx1950-jwm-app-menu" || die 'user .desktop applications are not discovered'
extract /usr/bin/mb-applet-xterm-wrapper.sh "$tmp/xterm-wrapper"
grep -Fq -- '-sb -rightbar -sl 1000' "$tmp/xterm-wrapper" || die 'terminal lacks scrollbar/scrollback profile'

# Keyboard, Wi-Fi and hardware controls must remain data driven.
extract /usr/bin/rx1950-keyboard "$tmp/rx1950-keyboard"
grep -Fq 'keyboard*.xml' "$tmp/rx1950-keyboard" || die 'on-screen keyboard layout list is hard-coded'
grep -Fq 'matchbox-keyboard --lang' "$tmp/rx1950-keyboard" || die 'on-demand keyboard helper does not launch Matchbox Keyboard'
extract /etc/default/rx1950-wlan "$tmp/rx1950-wlan-default"
grep -Fqx 'REGDOMAIN=' "$tmp/rx1950-wlan-default" || die 'rootfs hard-codes or omits WLAN country state'
extract /usr/sbin/rx1950-wlan "$tmp/rx1950-wlan"
grep -Fq 'wpa_supplicant -B -D wext' "$tmp/rx1950-wlan" || die 'ACX100-compatible WEXT association backend missing'
grep -Fq 'udhcpc -i "$ifname" -p "$DHCP_PIDFILE" -n -q' "$tmp/rx1950-wlan" || die 'WLAN DHCP is not bounded'
extract /usr/sbin/rx1950-control "$tmp/rx1950-control"
for token in 'wifi-country-set)' 'key-set)' 'panel-height-set)' 'dpi-set)' 'calibrate_touch'; do
    grep -Fq "$token" "$tmp/rx1950-control" || die "control center backend missing $token"
done

printf 'rootfs WLAN/USB/GUI/runtime payload: OK\n'

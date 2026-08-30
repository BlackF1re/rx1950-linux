#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

readonly TARGET_DIR="$1"
readonly EXTERNAL_DIR="$2"
readonly RELEASE_VERSION="${RX1950_RELEASE_VERSION:-devel}"
readonly PROJECT_DIR="$(cd "${EXTERNAL_DIR}/../../.." && pwd)"
readonly DOWNLOAD_DIR="${PROJECT_DIR}/dl"
readonly ACX_ARCHIVE="${DOWNLOAD_DIR}/acx-firmware-1.4p6.tgz"
readonly ACX_ARCHIVE_SHA256="47719a4ecb0e2a486e376e40fae8c79e56233b3cd88150e8c55a92879b4819a8"
readonly ACX_MAIN_SHA256="4f05913c940c2455b267545b12d93ad81fa5eebb0cbee22a2c7588c50525b4f0"
readonly ACX_RADIO0D_SHA256="6a4a7fbb24a328a88261bc2a507b2a0bf63c91e831e3f1a8caa4f6599b2215e6"
readonly ACX_RADIO11_SHA256="e005a93a0b463e01edba2b79038b54c29a7932efee61c851a2ac644b8a4e5dd4"

verify_sha256() {
    local file="$1" expected="$2"
    printf '%s  %s\n' "$expected" "$file" | sha256sum --check --status
}

install_acx_firmware() {
    local tmp main radio0d radio11
    mkdir -p "${TARGET_DIR}/lib/firmware"

    [[ -s "${ACX_ARCHIVE}" ]] || {
        echo 'verified ACX100 firmware archive was not prepared' >&2
        return 1
    }
    verify_sha256 "${ACX_ARCHIVE}" "${ACX_ARCHIVE_SHA256}" || {
        rm -f "${ACX_ARCHIVE}"
        echo 'ACX100 firmware archive checksum mismatch' >&2
        return 1
    }

    tmp="$(mktemp -d)"
    if ! tar -xzf "${ACX_ARCHIVE}" -C "${tmp}"; then
        rm -rf "$tmp"
        echo 'ACX100 firmware archive cannot be extracted' >&2
        return 1
    fi

    main="$(find "${tmp}" -type f -name tiacx100 -print -quit)"
    radio0d="$(find "${tmp}" -type f -name tiacx100r0D -print -quit)"
    radio11="$(find "${tmp}" -type f -name tiacx100r11 -print -quit)"
    [[ -n "$main" && -n "$radio0d" && -n "$radio11" ]] || {
        rm -f "${ACX_ARCHIVE}"
        rm -rf "$tmp"
        echo 'ACX100 firmware package is incomplete' >&2
        return 1
    }

    if ! verify_sha256 "$main" "$ACX_MAIN_SHA256" ||
       ! verify_sha256 "$radio0d" "$ACX_RADIO0D_SHA256" ||
       ! verify_sha256 "$radio11" "$ACX_RADIO11_SHA256"; then
        rm -f "${ACX_ARCHIVE}"
        rm -rf "$tmp"
        echo 'ACX100 firmware checksum mismatch' >&2
        return 1
    fi

    install -m 0644 "$main" "${TARGET_DIR}/lib/firmware/WLANGEN.BIN"
    install -m 0644 "$radio0d" "${TARGET_DIR}/lib/firmware/RADIO0d.BIN"
    install -m 0644 "$radio11" "${TARGET_DIR}/lib/firmware/RADIO11.BIN"
    touch -d "@${SOURCE_DATE_EPOCH:-1767225600}" \
        "${TARGET_DIR}/lib/firmware/WLANGEN.BIN" \
        "${TARGET_DIR}/lib/firmware/RADIO0d.BIN" \
        "${TARGET_DIR}/lib/firmware/RADIO11.BIN"
    rm -rf "$tmp"
}

install -d -m 0755 \
    "${TARGET_DIR}/proc" \
    "${TARGET_DIR}/sys" \
    "${TARGET_DIR}/dev" \
    "${TARGET_DIR}/tmp" \
    "${TARGET_DIR}/run" \
    "${TARGET_DIR}/mnt/data" \
    "${TARGET_DIR}/mnt/rx1950-boot" \
    "${TARGET_DIR}/lib/firmware" \
    "${TARGET_DIR}/usr/lib/rx1950" \
    "${TARGET_DIR}/var/lib/alsa" \
    "${TARGET_DIR}/var/lib/opkg/lists"
install -m 0644 "${EXTERNAL_DIR}/board/hp_rx1950/fstab" "${TARGET_DIR}/etc/fstab"
install_acx_firmware

printf '%s\n' "${SOURCE_DATE_EPOCH:-1767225600}" > "${TARGET_DIR}/usr/lib/rx1950/build-epoch"
date --utc --date="@${SOURCE_DATE_EPOCH:-1767225600}" '+%Y-%m-%d %H:%M:%S' \
    > "${TARGET_DIR}/usr/lib/rx1950/build-date-utc"

# Buildroot's generic X init script starts before our hardware-specific
# configuration and would race S48xserver for display :0.
rm -f "${TARGET_DIR}/etc/init.d/S40xorg"

# Buildroot normally derives /etc/os-release VERSION from the surrounding Git
# checkout. A pull-request synthetic merge and the equivalent squash commit have
# different commit IDs despite an identical source tree, which made otherwise
# identical root filesystems differ. Keep source identity in external provenance
# and make the runtime OS identity depend only on the requested release version.
cat > "${TARGET_DIR}/etc/os-release" <<EOF
NAME="rx1950-linux"
ID=rx1950-linux
VERSION="${RELEASE_VERSION}"
VERSION_ID="${RELEASE_VERSION}"
PRETTY_NAME="rx1950-linux ${RELEASE_VERSION}"
HOME_URL="https://github.com/BlackF1re/rx1950-linux"
EOF

chmod 0755 \
    "${TARGET_DIR}/etc/init.d/S02clock-sanity" \
    "${TARGET_DIR}/etc/init.d/S10kernel-modules" \
    "${TARGET_DIR}/etc/init.d/S20zram" \
    "${TARGET_DIR}/etc/init.d/S30alsa" \
    "${TARGET_DIR}/etc/init.d/S35usb-gadget" \
    "${TARGET_DIR}/etc/init.d/S38time-sync" \
    "${TARGET_DIR}/etc/init.d/S40wlan" \
    "${TARGET_DIR}/etc/init.d/S48xserver" \
    "${TARGET_DIR}/etc/init.d/S50matchbox" \
    "${TARGET_DIR}/usr/bin/mb-applet-xterm-wrapper.sh" \
    "${TARGET_DIR}/usr/bin/rx1950-keyboard" \
    "${TARGET_DIR}/usr/bin/rx1950-launch" \
    "${TARGET_DIR}/usr/bin/rx1950-settings-launcher" \
    "${TARGET_DIR}/usr/bin/rx1950-wifi-launcher" \
    "${TARGET_DIR}/usr/share/udhcpc/rx1950-usb.script" \
    "${TARGET_DIR}/usr/sbin/rx1950-usb-dhcp" \
    "${TARGET_DIR}/usr/sbin/rx1950-time-sync" \
    "${TARGET_DIR}/usr/sbin/rx1950-timezone" \
    "${TARGET_DIR}/usr/sbin/rx1950-wlan" \
    "${TARGET_DIR}/usr/sbin/rx1950-settings" \
    "${TARGET_DIR}/usr/sbin/rx1950-control" \
    "${TARGET_DIR}/usr/sbin/rx1950-wifi-ui" \
    "${TARGET_DIR}/usr/sbin/rx1950-wlan-firmware" \
    "${TARGET_DIR}/usr/sbin/rx1950-blue" \
    "${TARGET_DIR}/usr/sbin/rx1950-sensors"

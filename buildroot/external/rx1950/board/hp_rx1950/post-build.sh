#!/usr/bin/env bash
set -euo pipefail

readonly TARGET_DIR="$1"
readonly EXTERNAL_DIR="$2"

install -d -m 0755 \
    "${TARGET_DIR}/proc" \
    "${TARGET_DIR}/sys" \
    "${TARGET_DIR}/dev" \
    "${TARGET_DIR}/tmp" \
    "${TARGET_DIR}/run" \
    "${TARGET_DIR}/mnt/data" \
    "${TARGET_DIR}/mnt/rx1950-boot" \
    "${TARGET_DIR}/lib/firmware" \
    "${TARGET_DIR}/var/lib/opkg/lists"
install -m 0644 "${EXTERNAL_DIR}/board/hp_rx1950/fstab" "${TARGET_DIR}/etc/fstab"

chmod 0755 \
    "${TARGET_DIR}/etc/init.d/S10kernel-modules" \
    "${TARGET_DIR}/etc/init.d/S40wlan" \
    "${TARGET_DIR}/usr/sbin/rx1950-wlan" \
    "${TARGET_DIR}/usr/sbin/rx1950-wlan-firmware" \
    "${TARGET_DIR}/usr/sbin/rx1950-blue" \
    "${TARGET_DIR}/usr/sbin/rx1950-sensors"

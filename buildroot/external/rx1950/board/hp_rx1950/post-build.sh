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
    "${TARGET_DIR}/var/lib/opkg/lists"
install -m 0644 "${EXTERNAL_DIR}/board/hp_rx1950/fstab" "${TARGET_DIR}/etc/fstab"

#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

readonly TARGET_DIR="$1"
readonly EXTERNAL_DIR="$2"
readonly RELEASE_VERSION="${RX1950_RELEASE_VERSION:-devel}"

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
    "${TARGET_DIR}/etc/init.d/S10kernel-modules" \
    "${TARGET_DIR}/etc/init.d/S40wlan" \
    "${TARGET_DIR}/usr/sbin/rx1950-wlan" \
    "${TARGET_DIR}/usr/sbin/rx1950-wlan-firmware" \
    "${TARGET_DIR}/usr/sbin/rx1950-blue" \
    "${TARGET_DIR}/usr/sbin/rx1950-sensors"

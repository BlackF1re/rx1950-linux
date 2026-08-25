#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly OUTPUT_DIR="${ROOT_DIR}/output"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

case "${1:-source}" in
  source)
    test -s "${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
    test -s "${ROOT_DIR}/kernel/rx1950_defconfig"
    test -s "${ROOT_DIR}/board/hp_rx1950/startup.txt"
    git -C "${ROOT_DIR}" diff --check
    ;;
  image)
    test -s "${OUTPUT_DIR}/rx1950-linux-sd.img"
    test -s "${OUTPUT_DIR}/rx1950-linux-sd.img.xz"
    test -s "${OUTPUT_DIR}/SHA256SUMS"
    (cd "${OUTPUT_DIR}" && sha256sum --check SHA256SUMS)
    image="${OUTPUT_DIR}/rx1950-linux-sd.img"
    rootfs_size="$(stat --format='%s' "${OUTPUT_DIR}/rootfs.ext2")"
    test $((rootfs_size % 512)) -eq 0
    image_size="$(stat --format='%s' "${image}")"
    test "${image_size}" -eq $((34816 * 512 + rootfs_size))
    image_sectors=$((image_size / 512))
    partition_map="$(parted --machine --script "${image}" unit s print)"
    printf '%s\n' "${partition_map}" | grep -Eq '^1:2048s:34815s:32768s:'
    printf '%s\n' "${partition_map}" | grep -Eq "^2:34816s:$((image_sectors - 1))s:$((image_sectors - 34816))s:"
    dd if="${image}" bs=512 skip=34816 count=$((rootfs_size / 512)) status=none | \
      cmp --bytes="${rootfs_size}" "${OUTPUT_DIR}/rootfs.ext2" -
    xz --test "${image}.xz"
    xz --decompress --stdout "${image}.xz" | cmp --bytes="${image_size}" "${image}" -
    ;;
  *) die "usage: $0 {source|image}" ;;
esac

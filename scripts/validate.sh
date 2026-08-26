#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly OUTPUT_DIR="${ROOT_DIR}/output"
readonly IMAGE_NAME="${RX1950_IMAGE_NAME:-rx1950-linux-sd}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

case "${1:-source}" in
  source)
    test -s "${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
    test -s "${ROOT_DIR}/kernel/rx1950_defconfig"
    test -s "${ROOT_DIR}/kernel/patches/0002-s3c244x-restore-fclk-n-and-trace-uart.patch"
    test ! -e "${ROOT_DIR}/kernel/patches/0001-rx1950-add-early-led-boot-markers.patch"
    test ! -e "${ROOT_DIR}/kernel/patches/0002-rx1950-mark-zimage-entry-with-green-led.patch"
    grep -qx 'CONFIG_ARCH_MULTI_V4T=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx '# CONFIG_ARCH_MULTI_V7 is not set' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_UNUSED_BOARD_FILES=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_DMADEVICES=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_S3C24XX_DMAC=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_MMC_S3C=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx '# CONFIG_SERIAL_SAMSUNG_CONSOLE is not set' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -Fqx 'CONFIG_CMDLINE="root=/dev/mmcblk0p2 rootwait rw console=tty0 loglevel=8 ignore_loglevel initcall_debug consoleblank=0 printk.time=1"' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -Fq 'clk_uart_baud3' "${ROOT_DIR}/kernel/patches/0002-s3c244x-restore-fclk-n-and-trace-uart.patch"
    grep -Fq 'platform_get_irq_optional(platdev, 1)' "${ROOT_DIR}/kernel/patches/0002-s3c244x-restore-fclk-n-and-trace-uart.patch"
    test -s "${ROOT_DIR}/board/hp_rx1950/startup.txt"
    grep -qx 'set RAMADDR 0x30000000' "${ROOT_DIR}/board/hp_rx1950/startup.txt"
    grep -qx 'set RAMSIZE 32\*1024\*1024' "${ROOT_DIR}/board/hp_rx1950/startup.txt"
    grep -qx 'set MTYPE 952' "${ROOT_DIR}/board/hp_rx1950/startup.txt"
    grep -qx 'set KERNEL_OFFSET 0x1000000' "${ROOT_DIR}/board/hp_rx1950/startup.txt"
    grep -qx 'set FBDURINGBOOT 0' "${ROOT_DIR}/board/hp_rx1950/startup.txt"
    grep -qx 'set KERNELCRC 1' "${ROOT_DIR}/board/hp_rx1950/startup.txt"
    grep -Fqx 'set CMDLINE "root=/dev/mmcblk0p2 rootwait rw console=tty0 loglevel=8 ignore_loglevel initcall_debug consoleblank=0 printk.time=1"' "${ROOT_DIR}/board/hp_rx1950/startup.txt"
    test -x "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/init.d/S10boot-probe"
    test -x "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/sbin/rx1950-boot-probe"
    git -C "${ROOT_DIR}" diff --check
    ;;
  image)
    command -v mdir >/dev/null 2>&1 || die "missing required command: mdir"
    image="${OUTPUT_DIR}/${IMAGE_NAME}.img"
    test -s "${image}"
    test -s "${image}.xz"
    test -s "${OUTPUT_DIR}/SHA256SUMS"
    test -s "${OUTPUT_DIR}/boot.fat"
    mdir -i "${OUTPUT_DIR}/boot.fat" ::earlyharetlog.txt >/dev/null
    (cd "${OUTPUT_DIR}" && sha256sum --check SHA256SUMS)
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

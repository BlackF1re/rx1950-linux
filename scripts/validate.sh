#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly OUTPUT_DIR="${ROOT_DIR}/output"
readonly IMAGE_NAME="${RX1950_IMAGE_NAME:-rx1950-linux-sd}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

validate_patch_syntax() {
  python3 - "$@" <<'PY'
import pathlib
import re
import sys

header_re = re.compile(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@')

for filename in sys.argv[1:]:
    path = pathlib.Path(filename)
    lines = path.read_text(encoding='utf-8').splitlines()
    saw_hunk = False
    index = 0
    while index < len(lines):
        line = lines[index]
        if not line.startswith('@@ '):
            index += 1
            continue

        saw_hunk = True
        match = header_re.match(line)
        if not match:
            raise SystemExit(f'{path}: malformed hunk header at line {index + 1}: {line}')

        old_expected = int(match.group(2) or 1)
        new_expected = int(match.group(4) or 1)
        old_count = 0
        new_count = 0
        index += 1

        while index < len(lines):
            body = lines[index]
            if body.startswith('@@ ') or body.startswith('diff --git '):
                break
            if body.startswith(' '):
                old_count += 1
                new_count += 1
            elif body.startswith('-'):
                old_count += 1
            elif body.startswith('+'):
                new_count += 1
            elif body.startswith('\\ No newline at end of file'):
                pass
            else:
                raise SystemExit(
                    f'{path}: invalid unified-diff line at {index + 1}: {body!r}'
                )
            index += 1

        if (old_count, new_count) != (old_expected, new_expected):
            raise SystemExit(
                f'{path}: hunk count mismatch after line {index + 1}: '
                f'header expects {old_expected}/{new_expected}, '
                f'body contains {old_count}/{new_count}'
            )

    if not saw_hunk:
        raise SystemExit(f'{path}: patch contains no hunks')
PY
}

case "${1:-source}" in
  source)
    test -s "${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
    test -s "${ROOT_DIR}/kernel/rx1950_defconfig"
    test -s "${ROOT_DIR}/kernel/patches/0002-s3c244x-restore-fclk-n-and-trace-uart.patch"
    test ! -e "${ROOT_DIR}/kernel/patches/0001-rx1950-add-early-led-boot-markers.patch"
    test ! -e "${ROOT_DIR}/kernel/patches/0002-rx1950-mark-zimage-entry-with-green-led.patch"
    validate_patch_syntax "${ROOT_DIR}"/kernel/patches/*.patch
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

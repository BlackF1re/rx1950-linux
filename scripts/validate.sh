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

validate_abi_configs() {
    local kernel_config="$1" buildroot_config="$2"

    grep -qx 'CONFIG_AEABI=y' "${kernel_config}" ||
        die "kernel is not configured for the EABI used by the RX1950 rootfs"
    grep -qx '# CONFIG_OABI_COMPAT is not set' "${kernel_config}" ||
        die "kernel unexpectedly enables legacy OABI compatibility"
    grep -qx 'CONFIG_KUSER_HELPERS=y' "${kernel_config}" ||
        die "kernel lost ARM kuser helpers required by ARMv4T userspace"

    grep -qx 'BR2_arm920t=y' "${buildroot_config}" ||
        die "rootfs is not targeted at ARM920T"
    grep -qx 'BR2_ARM_EABI=y' "${buildroot_config}" ||
        die "rootfs is not using ARM EABI"
    grep -qx 'BR2_SOFT_FLOAT=y' "${buildroot_config}" ||
        die "rootfs is not using the RX1950 soft-float ABI"
    grep -qx 'BR2_ARM_INSTRUCTIONS_ARM=y' "${buildroot_config}" ||
        die "rootfs instruction mode drifted away from ARM"
    grep -qx 'BR2_TOOLCHAIN_BUILDROOT_MUSL=y' "${buildroot_config}" ||
        die "rootfs libc/toolchain contract changed"
}

validate_console_backlight_configs() {
    local kernel_config="$1" buildroot_config="$2"

    grep -qx 'CONFIG_TTY=y' "${kernel_config}" ||
        die "kernel dropped the TTY core required by the local console"
    grep -qx 'CONFIG_VT=y' "${kernel_config}" ||
        die "kernel dropped virtual terminal support required for tty1"
    grep -qx 'CONFIG_VT_CONSOLE=y' "${kernel_config}" ||
        die "kernel dropped the virtual terminal console"
    grep -qx 'CONFIG_DEVTMPFS=y' "${kernel_config}" ||
        die "kernel dropped devtmpfs; dynamic device nodes such as /dev/tty1 cannot exist"
    grep -qx 'CONFIG_DEVTMPFS_MOUNT=y' "${kernel_config}" ||
        die "kernel will not auto-mount devtmpfs on /dev"
    grep -qx 'CONFIG_BACKLIGHT_CLASS_DEVICE=y' "${kernel_config}" ||
        die "kernel dropped the backlight class; pwm-backlight cannot probe"
    grep -qx 'CONFIG_BACKLIGHT_PWM=y' "${kernel_config}" ||
        die "kernel dropped the RX1950 PWM backlight driver"
    grep -qx 'CONFIG_PWM_SAMSUNG=y' "${kernel_config}" ||
        die "kernel dropped the Samsung PWM controller"
    grep -qx '# CONFIG_SERIAL_SAMSUNG_CONSOLE is not set' "${kernel_config}" ||
        die "Samsung serial console was unexpectedly re-enabled"

    grep -qx 'BR2_TARGET_GENERIC_GETTY=y' "${buildroot_config}" ||
        die "rootfs lost the local getty"
    grep -qx 'BR2_TARGET_GENERIC_GETTY_PORT="tty1"' "${buildroot_config}" ||
        die "rootfs getty is not attached to framebuffer VT tty1"
    grep -qx 'BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_DEVTMPFS=y' "${buildroot_config}" ||
        die "rootfs device policy no longer uses zero-daemon kernel devtmpfs"
    ! grep -q 'BR2_TARGET_GENERIC_GETTY_PORT="ttySAC0"' "${buildroot_config}" ||
        die "rootfs still respawns getty on unavailable ttySAC0"
}

case "${1:-source}" in
  source)
    test -s "${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
    test -s "${ROOT_DIR}/kernel/rx1950_defconfig"
    test -s "${ROOT_DIR}/kernel/patches/0002-s3c244x-restore-fclk-n-and-trace-uart.patch"
    test -s "${ROOT_DIR}/kernel/patches/0003-s3c24xx-defer-uart-activation.patch"
    test ! -e "${ROOT_DIR}/kernel/patches/0001-rx1950-add-early-led-boot-markers.patch"
    test ! -e "${ROOT_DIR}/kernel/patches/0002-rx1950-mark-zimage-entry-with-green-led.patch"
    validate_patch_syntax "${ROOT_DIR}"/kernel/patches/*.patch \
      "${ROOT_DIR}"/buildroot/external/rx1950/patches/xterm/*.patch
    grep -qx 'BR2_arm920t=y' "${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
    grep -qx 'BR2_ARM_EABI=y' "${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
    grep -qx 'BR2_SOFT_FLOAT=y' "${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
    grep -qx 'BR2_ARM_INSTRUCTIONS_ARM=y' "${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
    grep -qx 'BR2_TOOLCHAIN_BUILDROOT_MUSL=y' "${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
    grep -qx 'BR2_PACKAGE_JWM=y' "${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
    ! grep -q '^BR2_PACKAGE_MATCHBOX_\(COMMON\|DESKTOP\|PANEL\)=y' "${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
    grep -qx 'BR2_PACKAGE_DIALOG=y' "${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
    grep -qx 'BR2_GLOBAL_PATCH_DIR="$(BR2_EXTERNAL_RX1950_PATH)/patches"' "${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
    grep -Fq 'defined(__linux__)' "${ROOT_DIR}/buildroot/external/rx1950/patches/xterm/0001-linux-musl-fix-pty-session-and-retry.patch"
    grep -qx 'BR2_TARGET_GENERIC_GETTY=y' "${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
    grep -qx 'BR2_TARGET_GENERIC_GETTY_PORT="tty1"' "${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
    grep -qx 'BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_DEVTMPFS=y' "${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
    ! grep -q 'ttySAC0' "${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
    grep -qx 'CONFIG_ARCH_MULTI_V4T=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx '# CONFIG_ARCH_MULTI_V7 is not set' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_UNUSED_BOARD_FILES=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_AEABI=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx '# CONFIG_OABI_COMPAT is not set' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_KUSER_HELPERS=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_BLK_DEV_INITRD=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_RD_GZIP=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_BINFMT_ELF=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_BINFMT_SCRIPT=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_CMDLINE_FROM_BOOTLOADER=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx '# CONFIG_CMDLINE_FORCE is not set' "${ROOT_DIR}/kernel/rx1950_defconfig"
    ! grep -Fq "printf '%s\\n' 'CONFIG_CMDLINE_FORCE=y'" "${ROOT_DIR}/scripts/build.sh"
    test -x "${ROOT_DIR}/scripts/build-recovery.sh"
    test -x "${ROOT_DIR}/scripts/recovery-init.sh"
    test -x "${ROOT_DIR}/scripts/recovery-write.sh"
    grep -Fq '( sleep 2700; reboot -f ) &' "${ROOT_DIR}/scripts/recovery-init.sh"
    grep -Fqx 'mkdir -p /var/run /tmp' "${ROOT_DIR}/scripts/recovery-init.sh"
    grep -Fqx 'chmod 1777 /tmp' "${ROOT_DIR}/scripts/recovery-init.sh"
    grep -Fqx 'CONFIG_NC=y' "${ROOT_DIR}/buildroot/external/rx1950/configs/busybox.fragment"
    grep -Fqx 'CONFIG_NC_SERVER=y' "${ROOT_DIR}/buildroot/external/rx1950/configs/busybox.fragment"
    grep -Fq 'nc -l -p 31337' "${ROOT_DIR}/scripts/recovery-init.sh"
    grep -Fq '/usr/sbin/rx1950-recovery-write' "${ROOT_DIR}/scripts/recovery-init.sh"
    grep -Fq 'progress_done=0' "${ROOT_DIR}/scripts/recovery-write.sh"
    ! grep -Fq 'render_progress "$phase" "$total" "$total"' "${ROOT_DIR}/scripts/recovery-write.sh"
    grep -Fq 'dd of=/dev/mmcblk0 bs=1048576 <&0 &' "${ROOT_DIR}/scripts/recovery-write.sh"
    ! grep -Fq 'dropbear' "${ROOT_DIR}/scripts/recovery-init.sh"
    test -s "${ROOT_DIR}/board/hp_rx1950/startup-recovery.txt"
    ! grep -q '^set INITRD ' "${ROOT_DIR}/board/hp_rx1950/startup-recovery.txt"
    grep -Fq 'zImage-recovery' "${ROOT_DIR}/tools/update-rx1950.sh"
    grep -Fq 'CONFIG_INITRAMFS_SOURCE' "${ROOT_DIR}/scripts/build.sh"
    grep -qx 'sleep 10000' "${ROOT_DIR}/board/hp_rx1950/startup-recovery.txt"
    grep -qx 'CONFIG_TTY=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_VT=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_VT_CONSOLE=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_DEVTMPFS=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_DEVTMPFS_MOUNT=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_DMADEVICES=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_S3C24XX_DMAC=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_MMC_S3C=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_BACKLIGHT_CLASS_DEVICE=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_BACKLIGHT_PWM=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_PWM_SAMSUNG=y' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx 'CONFIG_LOG_BUF_SHIFT=14' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx '# CONFIG_DEBUG_KERNEL is not set' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -qx '# CONFIG_SERIAL_SAMSUNG_CONSOLE is not set' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -Fqx 'CONFIG_CMDLINE="root=/dev/mmcblk0p2 rootwait rw console=tty0 loglevel=4 consoleblank=0"' "${ROOT_DIR}/kernel/rx1950_defconfig"
    grep -Fq 'clk_uart_baud3' "${ROOT_DIR}/kernel/patches/0002-s3c244x-restore-fclk-n-and-trace-uart.patch"
    grep -Fq 'platform_get_irq_optional(platdev, 1)' "${ROOT_DIR}/kernel/patches/0002-s3c244x-restore-fclk-n-and-trace-uart.patch"
    grep -Fq 'deferring RX/TX controller activation until IRQ startup' "${ROOT_DIR}/kernel/patches/0003-s3c24xx-defer-uart-activation.patch"
    grep -Fq 'both IRQ handlers installed; activating RX/TX modes' "${ROOT_DIR}/kernel/patches/0003-s3c24xx-defer-uart-activation.patch"
    grep -Fq 'reset: writing UCON=' "${ROOT_DIR}/kernel/patches/0003-s3c24xx-defer-uart-activation.patch"
    test -s "${ROOT_DIR}/board/hp_rx1950/startup.txt"
    grep -qx 'set RAMADDR 0x30000000' "${ROOT_DIR}/board/hp_rx1950/startup.txt"
    grep -qx 'set RAMSIZE 32\*1024\*1024' "${ROOT_DIR}/board/hp_rx1950/startup.txt"
    grep -qx 'set MTYPE 952' "${ROOT_DIR}/board/hp_rx1950/startup.txt"
    grep -qx 'set KERNEL_OFFSET 0x1000000' "${ROOT_DIR}/board/hp_rx1950/startup.txt"
    grep -qx 'set FBDURINGBOOT 0' "${ROOT_DIR}/board/hp_rx1950/startup.txt"
    grep -qx 'set KERNELCRC 1' "${ROOT_DIR}/board/hp_rx1950/startup.txt"
    grep -Fqx 'set CMDLINE "root=/dev/mmcblk0p2 rootwait rw console=tty0 loglevel=4 consoleblank=0"' "${ROOT_DIR}/board/hp_rx1950/startup.txt"
    grep -qx 'sleep 10000' "${ROOT_DIR}/board/hp_rx1950/startup.txt"
    test -x "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/init.d/S10boot-probe"
    test -x "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/sbin/rx1950-boot-probe"
    grep -Fq 'dmesg.log' "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/sbin/rx1950-boot-probe"
    grep -Fq '/proc/interrupts' "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/sbin/rx1950-boot-probe"
    grep -Fq 'set_backlight_max' "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/sbin/rx1950-boot-probe"
    grep -Fq '/sys/class/backlight/' "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/sbin/rx1950-boot-probe"
    git -C "${ROOT_DIR}" diff --check
    ;;
  image)
    command -v mdir >/dev/null 2>&1 || die "missing required command: mdir"
    command -v debugfs >/dev/null 2>&1 || die "missing required command: debugfs"
    command -v readelf >/dev/null 2>&1 || die "missing required command: readelf"
    image="${OUTPUT_DIR}/${IMAGE_NAME}.img"
    test -s "${image}"
    test -s "${image}.xz"
    test -s "${OUTPUT_DIR}/SHA256SUMS"
    test -s "${OUTPUT_DIR}/boot.fat"
    test -s "${OUTPUT_DIR}/kernel.config"
    test -s "${OUTPUT_DIR}/buildroot.config"
    validate_abi_configs "${OUTPUT_DIR}/kernel.config" "${OUTPUT_DIR}/buildroot.config"
    validate_console_backlight_configs "${OUTPUT_DIR}/kernel.config" "${OUTPUT_DIR}/buildroot.config"
    grep -qx 'BR2_GCC_TARGET_CPU="arm920t"' "${OUTPUT_DIR}/buildroot.config" ||
      die "generated rootfs toolchain is not pinned to ARM920T"

    busybox_elf="$(mktemp)"
    inittab_file="$(mktemp)"
    trap 'rm -f "${busybox_elf}" "${inittab_file}"' EXIT
    debugfs -R "dump -p /bin/busybox ${busybox_elf}" "${OUTPUT_DIR}/rootfs.ext2" >/dev/null 2>&1 ||
      die "cannot extract BusyBox from rootfs for ABI verification"
    debugfs -R 'stat /usr/bin/nc' "${OUTPUT_DIR}/rootfs.ext2" 2>/dev/null |
      grep -Fq 'Inode:' ||
      die "BusyBox lacks the recovery netcat applet"
    readelf -h "${busybox_elf}" | grep -Eq 'Machine:[[:space:]]+ARM' ||
      die "BusyBox is not an ARM ELF"
    readelf -h "${busybox_elf}" | grep -Eq 'Flags:.*Version5 EABI.*soft-float ABI' ||
      die "BusyBox is not ARM EABI5 soft-float"
    readelf -A "${busybox_elf}" | grep -Fq 'Tag_CPU_arch: v4T' ||
      die "BusyBox contains the wrong ARM ISA level; ARM920T requires ARMv4T"

    debugfs -R "dump -p /etc/inittab ${inittab_file}" "${OUTPUT_DIR}/rootfs.ext2" >/dev/null 2>&1 ||
      die "cannot extract /etc/inittab from rootfs"
    grep -Eq '^tty1::respawn:' "${inittab_file}" ||
      die "rootfs does not spawn the local getty on tty1"
    ! grep -q 'ttySAC0' "${inittab_file}" ||
      die "rootfs still contains a ttySAC0 respawn entry"

    mdir -i "${OUTPUT_DIR}/boot.fat" ::earlyharetlog.txt >/dev/null
    mdir -i "${OUTPUT_DIR}/boot.fat" ::zImage-recovery >/dev/null
    test -s "${OUTPUT_DIR}/recovery-kernel.config"
    grep -Fqx 'CONFIG_INITRAMFS_SOURCE="rx1950-recovery.cpio"' "${OUTPUT_DIR}/recovery-kernel.config"
    grep -Fqx 'CONFIG_INITRAMFS_FORCE=y' "${OUTPUT_DIR}/recovery-kernel.config"
    grep -Fqx 'CONFIG_CMDLINE_FORCE=y' "${OUTPUT_DIR}/recovery-kernel.config"
    grep -Fqx 'CONFIG_CMDLINE="rdinit=/init console=tty0 loglevel=4 consoleblank=0"' "${OUTPUT_DIR}/recovery-kernel.config"
    grep -Fqx '# CONFIG_CMDLINE_FROM_BOOTLOADER is not set' "${OUTPUT_DIR}/recovery-kernel.config"
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

#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly OUTPUT_DIR="${ROOT_DIR}/output"
readonly IMAGE_NAME="${RX1950_IMAGE_NAME:-rx1950-linux-sd}"
readonly RCFG="${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
readonly KCFG="${ROOT_DIR}/kernel/rx1950_defconfig"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
require_line() { grep -Fqx -- "$1" "$2" || die "${3:-missing '$1' in $2}"; }
require_fragment() { grep -Fq -- "$1" "$2" || die "${3:-missing '$1' in $2}"; }

validate_patch_syntax() {
    python3 - "$@" <<'PY'
import pathlib
import re
import sys

header = re.compile(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@')
for filename in sys.argv[1:]:
    path = pathlib.Path(filename)
    lines = path.read_text(encoding='utf-8').splitlines()
    saw_hunk = False
    i = 0
    while i < len(lines):
        if not lines[i].startswith('@@ '):
            i += 1
            continue
        saw_hunk = True
        match = header.match(lines[i])
        if not match:
            raise SystemExit(f'{path}: malformed hunk header at line {i + 1}')
        old_expected = int(match.group(2) or 1)
        new_expected = int(match.group(4) or 1)
        old_count = new_count = 0
        i += 1
        while i < len(lines) and not lines[i].startswith(('@@ ', 'diff --git ')):
            line = lines[i]
            if line.startswith(' '):
                old_count += 1; new_count += 1
            elif line.startswith('-'):
                old_count += 1
            elif line.startswith('+'):
                new_count += 1
            elif line.startswith('\\ No newline at end of file'):
                pass
            else:
                raise SystemExit(f'{path}: invalid diff line {i + 1}: {line!r}')
            i += 1
        if (old_count, new_count) != (old_expected, new_expected):
            raise SystemExit(
                f'{path}: hunk count mismatch: expected '
                f'{old_expected}/{new_expected}, got {old_count}/{new_count}'
            )
    if not saw_hunk:
        raise SystemExit(f'{path}: patch contains no hunks')
PY
}

validate_abi_configs() {
    local kernel_config="$1" buildroot_config="$2"
    require_line 'CONFIG_AEABI=y' "$kernel_config" 'kernel is not ARM EABI'
    require_line '# CONFIG_OABI_COMPAT is not set' "$kernel_config" 'legacy OABI unexpectedly enabled'
    require_line 'CONFIG_KUSER_HELPERS=y' "$kernel_config" 'ARMv4T kuser helpers missing'
    require_line 'BR2_arm920t=y' "$buildroot_config" 'rootfs is not ARM920T'
    require_line 'BR2_ARM_EABI=y' "$buildroot_config" 'rootfs is not ARM EABI'
    require_line 'BR2_SOFT_FLOAT=y' "$buildroot_config" 'rootfs is not soft-float'
    require_line 'BR2_ARM_INSTRUCTIONS_ARM=y' "$buildroot_config" 'rootfs instruction mode changed'
    require_line 'BR2_TOOLCHAIN_BUILDROOT_MUSL=y' "$buildroot_config" 'rootfs libc changed'
}

validate_console_config() {
    local kernel_config="$1" buildroot_config="$2"
    for line in CONFIG_TTY=y CONFIG_VT=y CONFIG_VT_CONSOLE=y CONFIG_DEVTMPFS=y CONFIG_DEVTMPFS_MOUNT=y; do
        require_line "$line" "$kernel_config" "local console contract dropped: $line"
    done
    require_line '# CONFIG_SERIAL_SAMSUNG_CONSOLE is not set' "$kernel_config" 'UART console unexpectedly enabled'
    require_line 'BR2_TARGET_GENERIC_GETTY=y' "$buildroot_config" 'local getty disabled'
    require_line 'BR2_TARGET_GENERIC_GETTY_PORT="tty1"' "$buildroot_config" 'local getty is not tty1'
    ! grep -Fq 'ttySAC0' "$buildroot_config" || die 'rootfs still references ttySAC0'
}

validate_source() {
    test -s "$RCFG" || die 'Buildroot defconfig missing'
    test -s "$KCFG" || die 'kernel defconfig missing'

    validate_abi_configs "$KCFG" "$RCFG"
    validate_console_config "$KCFG" "$RCFG"

    # Reproducible/minimal rootfs fundamentals.
    require_line 'BR2_REPRODUCIBLE=y' "$RCFG"
    require_line 'BR2_CCACHE=y' "$RCFG"
    require_line 'BR2_TARGET_GENERIC_ROOT_PASSWD=""' "$RCFG"
    require_line 'BR2_SYSTEM_BIN_SH_BUSYBOX=y' "$RCFG"
    require_line 'BR2_ROOTFS_POST_BUILD_SCRIPT="$(BR2_EXTERNAL_RX1950_PATH)/board/hp_rx1950/post-build.sh"' "$RCFG"
    require_line 'BR2_GLOBAL_PATCH_DIR="$(BR2_EXTERNAL_RX1950_PATH)/patches"' "$RCFG"
    require_line 'BR2_TARGET_ROOTFS_EXT2_SIZE="128M"' "$RCFG"

    # Normal kernel accepts HaRET's root command line; recovery is separately
    # sealed into an initramfs and force-pins rdinit there.
    require_line 'CONFIG_CMDLINE_FROM_BOOTLOADER=y' "$KCFG"
    require_line '# CONFIG_CMDLINE_FORCE is not set' "$KCFG"
    require_line 'CONFIG_BLK_DEV_INITRD=y' "$KCFG"
    require_line 'CONFIG_RD_GZIP=y' "$KCFG"
    require_line 'CONFIG_BINFMT_ELF=y' "$KCFG"
    require_line 'CONFIG_BINFMT_SCRIPT=y' "$KCFG"
    ! grep -Fq "printf '%s\\n' 'CONFIG_CMDLINE_FORCE=y'" "${ROOT_DIR}/scripts/build.sh" || die 'normal build script force-enables kernel command line'

    for file in \
        "${ROOT_DIR}/kernel/patches/0002-s3c244x-restore-fclk-n-and-trace-uart.patch" \
        "${ROOT_DIR}/kernel/patches/0003-s3c24xx-defer-uart-activation.patch" \
        "${ROOT_DIR}/buildroot/external/rx1950/patches/xterm/0001-linux-musl-fix-pty-session-and-retry.patch"; do
        test -s "$file" || die "required patch missing: $file"
    done
    validate_patch_syntax "${ROOT_DIR}"/kernel/patches/*.patch "${ROOT_DIR}"/buildroot/external/rx1950/patches/xterm/*.patch

    # HaRET layout is part of the boot ABI for this machine.
    local startup="${ROOT_DIR}/board/hp_rx1950/startup.txt"
    local recovery_startup="${ROOT_DIR}/board/hp_rx1950/startup-recovery.txt"
    test -s "$startup" || die 'startup.txt missing'
    test -s "$recovery_startup" || die 'startup-recovery.txt missing'
    require_line 'set RAMADDR 0x30000000' "$startup"
    require_line 'set RAMSIZE 32*1024*1024' "$startup"
    require_line 'set MTYPE 952' "$startup"
    require_line 'set KERNEL_OFFSET 0x1000000' "$startup"
    require_line 'set FBDURINGBOOT 0' "$startup"
    require_line 'set KERNELCRC 1' "$startup"
    require_line 'set CMDLINE "root=/dev/mmcblk0p2 rootwait rw console=tty0 loglevel=4 consoleblank=0"' "$startup"
    require_line 'sleep 10000' "$startup"
    ! grep -q '^set INITRD ' "$recovery_startup" || die 'recovery HaRET script must use self-contained kernel initramfs'
    require_line 'sleep 10000' "$recovery_startup"

    for file in scripts/build-recovery.sh scripts/recovery-init.sh scripts/recovery-write.sh tools/update-rx1950.sh; do
        test -x "${ROOT_DIR}/${file}" || die "required executable missing: $file"
        bash -n "${ROOT_DIR}/${file}" || die "invalid shell syntax: $file"
    done
    require_fragment '( sleep 2700; reboot -f ) &' "${ROOT_DIR}/scripts/recovery-init.sh" 'recovery watchdog missing'
    require_fragment 'nc -l -p 31337' "${ROOT_DIR}/scripts/recovery-init.sh" 'recovery transfer listener missing'
    require_fragment 'dd of=/dev/mmcblk0 bs=1048576 <&0 &' "${ROOT_DIR}/scripts/recovery-write.sh" 'streaming recovery writer missing'
    ! grep -Fq 'dropbear' "${ROOT_DIR}/scripts/recovery-init.sh" || die 'recovery must not expose Dropbear'

    # The source contract is split by concern. These are deliberately invoked
    # here too so a local `validate.sh source` is a useful pre-push gate.
    bash "${ROOT_DIR}/scripts/validate-peripherals.sh" source
    bash "${ROOT_DIR}/scripts/validate-opkg-feed.sh" source
    bash "${ROOT_DIR}/scripts/validate-reproducible.sh" source

    git -C "$ROOT_DIR" diff --check
}

validate_image() {
    command -v mdir >/dev/null 2>&1 || die 'mtools/mkdir is required'
    command -v debugfs >/dev/null 2>&1 || die 'debugfs is required'
    command -v readelf >/dev/null 2>&1 || die 'readelf is required'
    command -v parted >/dev/null 2>&1 || die 'parted is required'
    local image="${OUTPUT_DIR}/${IMAGE_NAME}.img"
    test -s "$image" || die "image missing: $image"
    test -s "${image}.xz" || die 'compressed image missing'
    test -s "${OUTPUT_DIR}/SHA256SUMS" || die 'image checksums missing'
    test -s "${OUTPUT_DIR}/boot.fat" || die 'boot filesystem missing'
    test -s "${OUTPUT_DIR}/rootfs.ext2" || die 'rootfs image missing'
    test -s "${OUTPUT_DIR}/kernel.config" || die 'generated kernel config missing'
    test -s "${OUTPUT_DIR}/buildroot.config" || die 'generated Buildroot config missing'

    validate_abi_configs "${OUTPUT_DIR}/kernel.config" "${OUTPUT_DIR}/buildroot.config"
    validate_console_config "${OUTPUT_DIR}/kernel.config" "${OUTPUT_DIR}/buildroot.config"
    require_line 'BR2_GCC_TARGET_CPU="arm920t"' "${OUTPUT_DIR}/buildroot.config" 'toolchain CPU is not pinned to ARM920T'

    local busybox_elf inittab
    busybox_elf="$(mktemp)"; inittab="$(mktemp)"
    trap 'rm -f "$busybox_elf" "$inittab"' EXIT
    debugfs -R "dump -p /bin/busybox ${busybox_elf}" "${OUTPUT_DIR}/rootfs.ext2" >/dev/null 2>&1 || die 'cannot extract BusyBox'
    readelf -h "$busybox_elf" | grep -Eq 'Machine:[[:space:]]+ARM' || die 'BusyBox is not ARM ELF'
    readelf -h "$busybox_elf" | grep -Eq 'Flags:.*Version5 EABI.*soft-float ABI' || die 'BusyBox is not EABI5 soft-float'
    readelf -A "$busybox_elf" | grep -Fq 'Tag_CPU_arch: v4T' || die 'BusyBox is not ARMv4T'
    debugfs -R "dump -p /etc/inittab ${inittab}" "${OUTPUT_DIR}/rootfs.ext2" >/dev/null 2>&1 || die 'cannot extract inittab'
    grep -Eq '^tty1::respawn:' "$inittab" || die 'tty1 getty missing from sealed rootfs'
    ! grep -q 'ttySAC0' "$inittab" || die 'sealed rootfs still respawns ttySAC0'

    mdir -i "${OUTPUT_DIR}/boot.fat" ::earlyharetlog.txt >/dev/null || die 'boot.fat lacks earlyharetlog.txt'
    mdir -i "${OUTPUT_DIR}/boot.fat" ::zImage-recovery >/dev/null || die 'boot.fat lacks recovery kernel'
    test -s "${OUTPUT_DIR}/recovery-kernel.config" || die 'recovery kernel config missing'
    require_line 'CONFIG_INITRAMFS_SOURCE="rx1950-recovery.cpio"' "${OUTPUT_DIR}/recovery-kernel.config"
    require_line 'CONFIG_INITRAMFS_FORCE=y' "${OUTPUT_DIR}/recovery-kernel.config"
    require_line 'CONFIG_CMDLINE_FORCE=y' "${OUTPUT_DIR}/recovery-kernel.config"
    require_line 'CONFIG_CMDLINE="rdinit=/init console=tty0 loglevel=4 consoleblank=0"' "${OUTPUT_DIR}/recovery-kernel.config"
    require_line '# CONFIG_CMDLINE_FROM_BOOTLOADER is not set' "${OUTPUT_DIR}/recovery-kernel.config"

    (cd "$OUTPUT_DIR" && sha256sum --check SHA256SUMS)
    local rootfs_size image_size image_sectors partition_map
    rootfs_size="$(stat --format='%s' "${OUTPUT_DIR}/rootfs.ext2")"
    (( rootfs_size % 512 == 0 )) || die 'rootfs image is not sector-aligned'
    image_size="$(stat --format='%s' "$image")"
    [[ "$image_size" -eq $((34816 * 512 + rootfs_size)) ]] || die 'assembled image size does not match partition layout'
    image_sectors=$((image_size / 512))
    partition_map="$(parted --machine --script "$image" unit s print)"
    grep -Eq '^1:2048s:34815s:32768s:' <<<"$partition_map" || die 'boot partition layout changed'
    grep -Eq "^2:34816s:$((image_sectors - 1))s:$((image_sectors - 34816))s:" <<<"$partition_map" || die 'root partition layout changed'
    dd if="$image" bs=512 skip=34816 count=$((rootfs_size / 512)) status=none | cmp --bytes="$rootfs_size" "${OUTPUT_DIR}/rootfs.ext2" -
    xz --test "${image}.xz"
    xz --decompress --stdout "${image}.xz" | cmp --bytes="$image_size" "$image" -

    rm -f "$busybox_elf" "$inittab"; trap - EXIT
}

case "${1:-source}" in
    source) validate_source ;;
    image) validate_image ;;
    *) die 'usage: validate.sh {source|image}' ;;
esac

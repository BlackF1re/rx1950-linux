#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly OUTPUT_DIR="${ROOT_DIR}/output"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
require_line() {
    local line="$1" file="$2" message="$3"
    grep -Fqx "$line" "$file" || die "$message"
}
require_fragment() {
    local fragment="$1" file="$2" message="$3"
    grep -Fq "$fragment" "$file" || die "$message"
}
rootfs_has() {
    local image="$1" path="$2"
    debugfs -R "stat ${path}" "$image" 2>&1 | grep -q 'Inode:'
}

case "${1:-source}" in
    source)
        kernel_defconfig="${ROOT_DIR}/kernel/rx1950_defconfig"
        rootfs_defconfig="${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
        grow_script="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/init.d/S05grow-root"
        usb_script="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/init.d/S35usb-gadget"
        dhcp_script="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/share/udhcpc/rx1950-usb.script"

        require_line 'CONFIG_S3C_ADC=y' "$kernel_defconfig" 'RX1950 ADC is not requested'
        require_line 'CONFIG_TOUCHSCREEN_S3C2410=y' "$kernel_defconfig" 'RX1950 touchscreen is not requested'
        require_line 'CONFIG_BATTERY_S3C_ADC=y' "$kernel_defconfig" 'RX1950 battery monitor is not requested'
        require_line 'CONFIG_RTC_DRV_S3C=y' "$kernel_defconfig" 'RX1950 RTC is not requested'
        require_line 'CONFIG_SND_SOC_SAMSUNG_RX1950_UDA1380=y' "$kernel_defconfig" 'RX1950 audio card is not requested'

        require_fragment 'depends on !ARCH_MULTIPLATFORM || ARCH_S3C24XX' \
            "${ROOT_DIR}/kernel/patches/0006-s3c24xx-restore-adc-multiplatform.patch" \
            'S3C24xx multiplatform ADC compatibility patch is missing'
        require_fragment 'nr_irqs - S3C2410_IRQSUB(0)' \
            "${ROOT_DIR}/kernel/patches/0007-s3c24xx-fix-static-irq-domain-size.patch" \
            'S3C24xx IRQ-domain bound is missing'
        require_fragment 's3c_rtc_driver_ids' \
            "${ROOT_DIR}/kernel/patches/0008-s3c-rtc-restore-platform-data-matching.patch" \
            'legacy S3C RTC platform matching is missing'
        require_fragment '{"Right ADC", NULL, "Right PGA"}' \
            "${ROOT_DIR}/kernel/patches/0009-uda1380-fix-right-adc-dapm-route.patch" \
            'UDA1380 modern DAPM route fix is missing'

        require_line 'BR2_PACKAGE_HTOP=y' "$rootfs_defconfig" 'htop is missing from the engineering image'
        require_line 'BR2_PACKAGE_EVTEST=y' "$rootfs_defconfig" 'evtest is missing from the engineering image'
        require_line 'BR2_PACKAGE_I2C_TOOLS=y' "$rootfs_defconfig" 'i2c-tools are missing from the engineering image'
        require_line 'BR2_PACKAGE_STRACE=y' "$rootfs_defconfig" 'strace is missing from the engineering image'
        require_line 'BR2_TARGET_ROOTFS_EXT2_SIZE="64M"' "$rootfs_defconfig" 'rootfs seed size is not 64 MiB'

        require_fragment '/proc/self/mountinfo' "$grow_script" 'root grower still relies on the /dev/root alias'
        require_fragment '/sys/class/block/mmcblk0p2/dev' "$grow_script" 'root grower does not verify the mounted block device'
        require_fragment 'udhcpc -i usb0' "$usb_script" 'USB DHCP client is not started'
        require_fragment '192.168.7.2/24' "$usb_script" 'fixed USB recovery address was lost'
        require_fragment 'rx1950-usb-dhcp' "$dhcp_script" 'USB DHCP event handler is missing'
        require_fragment 'ip route replace default' "$dhcp_script" 'USB host default route handling is missing'
        ;;

    kernel)
        config="${2:-${OUTPUT_DIR}/kernel.config}"
        require_line 'CONFIG_S3C_ADC=y' "$config" 'generated kernel dropped S3C ADC'
        require_line 'CONFIG_TOUCHSCREEN_S3C2410=y' "$config" 'generated kernel dropped the touchscreen driver'
        require_line 'CONFIG_BATTERY_S3C_ADC=y' "$config" 'generated kernel dropped the battery driver'
        require_line 'CONFIG_RTC_DRV_S3C=y' "$config" 'generated kernel dropped the RTC driver'
        require_line 'CONFIG_SND_SOC_SAMSUNG_RX1950_UDA1380=y' "$config" 'generated kernel dropped RX1950 audio'
        require_line 'CONFIG_USB_G_NCM=y' "$config" 'generated kernel dropped CDC-NCM recovery networking'
        ;;

    rootfs)
        config="${2:-${OUTPUT_DIR}/buildroot.config}"
        require_line 'BR2_PACKAGE_HTOP=y' "$config" 'generated rootfs dropped htop'
        require_line 'BR2_PACKAGE_EVTEST=y' "$config" 'generated rootfs dropped evtest'
        require_line 'BR2_PACKAGE_I2C_TOOLS=y' "$config" 'generated rootfs dropped i2c-tools'
        require_line 'BR2_PACKAGE_STRACE=y' "$config" 'generated rootfs dropped strace'
        require_line 'BR2_TARGET_ROOTFS_EXT2_SIZE="64M"' "$config" 'generated rootfs seed is not 64 MiB'
        ;;

    image)
        command -v debugfs >/dev/null 2>&1 || die 'debugfs is required for peripheral image validation'
        rootfs="${OUTPUT_DIR}/rootfs.ext2"
        test -s "$rootfs" || die 'rootfs.ext2 is missing'

        for path in /usr/bin/htop /usr/bin/evtest /usr/sbin/i2cdetect /usr/bin/strace \
                    /sbin/udhcpc /usr/share/udhcpc/rx1950-usb.script \
                    /etc/init.d/S05grow-root /etc/init.d/S35usb-gadget; do
            rootfs_has "$rootfs" "$path" || die "sealed rootfs is missing ${path}"
        done
        ;;

    *)
        die 'usage: validate-peripherals.sh {source|kernel [config]|rootfs [config]|image}'
        ;;
esac

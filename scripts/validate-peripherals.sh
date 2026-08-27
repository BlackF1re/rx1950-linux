#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly OUTPUT_DIR="${ROOT_DIR}/output"
readonly ACX_COMMIT="a282ba2502ac3b10cb6dbf16a35f7ad54e759779"

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
        modules_script="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/init.d/S10kernel-modules"
        usb_script="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/init.d/S35usb-gadget"
        wlan_init="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/init.d/S40wlan"
        dhcp_script="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/share/udhcpc/rx1950-usb.script"
        sensors_script="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/sbin/rx1950-sensors"
        wlan_script="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/sbin/rx1950-wlan"
        firmware_script="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/sbin/rx1950-wlan-firmware"
        blue_script="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/sbin/rx1950-blue"
        wlan_glue="${ROOT_DIR}/kernel/modules/rx1950-acx/rx1950_acx.c"
        build_script="${ROOT_DIR}/scripts/build.sh"
        opkg_conf="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/opkg/opkg.conf"
        hwmon_patch="${ROOT_DIR}/kernel/patches/0010-rx1950-enable-hwmon.patch"
        blue_patch="${ROOT_DIR}/kernel/patches/0011-rx1950-decouple-blue-led.patch"
        unsafe_mmc_patch="${ROOT_DIR}/kernel/patches/0011-s3cmci-fix-gpiod-return-handling.patch"

        require_line 'CONFIG_S3C_ADC=y' "$kernel_defconfig" 'RX1950 ADC is not requested'
        require_line 'CONFIG_TOUCHSCREEN_S3C2410=y' "$kernel_defconfig" 'RX1950 touchscreen is not requested'
        require_line 'CONFIG_BATTERY_S3C_ADC=y' "$kernel_defconfig" 'RX1950 battery monitor is not requested'
        require_line 'CONFIG_RTC_DRV_S3C=y' "$kernel_defconfig" 'RX1950 RTC is not requested'
        require_line 'CONFIG_SND_SOC_SAMSUNG_RX1950_UDA1380=y' "$kernel_defconfig" 'RX1950 audio card is not requested'
        require_line 'CONFIG_MMC_S3C_PIO=y' "$kernel_defconfig" 'RX1950 SD path is not pinned to proven PIO transfers'
        require_line '# CONFIG_MMC_S3C_DMA is not set' "$kernel_defconfig" 'RX1950 SD DMA must remain disabled'
        require_line 'CONFIG_I2C_CHARDEV=y' "$kernel_defconfig" 'I2C userspace character device support is missing'
        require_line 'CONFIG_HWMON=y' "$kernel_defconfig" 'hwmon core is missing'
        require_line 'CONFIG_SENSORS_S3C=y' "$kernel_defconfig" 'S3C ADC hwmon driver is missing'
        require_line 'CONFIG_SENSORS_S3C_RAW=y' "$kernel_defconfig" 'raw S3C ADC channels are not exposed'
        require_line 'CONFIG_MODULES=y' "$kernel_defconfig" 'kernel module support is missing'
        require_line 'CONFIG_FW_LOADER=y' "$kernel_defconfig" 'firmware loader support is missing'
        require_line 'CONFIG_MAC80211=y' "$kernel_defconfig" 'mac80211 is missing'
        require_line 'CONFIG_LEDS_TRIGGER_NETDEV=y' "$kernel_defconfig" 'netdev LED trigger is missing'

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
        require_fragment 'select S3C_DEV_HWMON' "$hwmon_patch" \
            'RX1950 hwmon platform device selection is missing'
        require_fragment 's3c_hwmon_set_platdata(&rx1950_hwmon_pdata);' "$hwmon_patch" \
            'RX1950 hwmon platform data is missing'
        require_fragment '.mult = 4235' "$hwmon_patch" \
            'RX1950 battery-voltage hwmon scaling is missing'
        require_fragment 'WARN_ON(platform_device_register(&s3c_device_hwmon));' "$hwmon_patch" \
            'RX1950 hwmon is not isolated from the boot-critical device array'
        if grep -Fq '&s3c2410_device_dma,' "$hwmon_patch"; then
            die 'experimental DMA device must not be registered in the RX1950 boot path'
        fi
        if grep -Fq '&s3c_device_hwmon,' "$hwmon_patch"; then
            die 'optional hwmon device must not be part of the rollback-prone RX1950 device array'
        fi
        [[ ! -e "$unsafe_mmc_patch" ]] ||
            die 'unsafe S3CMCI GPIO control-flow patch must remain reverted'

        # WLAN must remain entirely outside the boot-critical board array.
        require_fragment '.default_trigger' "$blue_patch" 'Blue LED decoupling patch is missing'
        require_fragment '+		.default_trigger	= NULL,' "$blue_patch" 'Blue LED still has a hard WLAN trigger'
        require_fragment '#define RX1950_WLAN_BASE          0x20000000' "$wlan_glue" 'RX1950 ACX MMIO resource is missing'
        require_fragment '#define RX1950_WLAN_RESET         S3C2410_GPA(14)' "$wlan_glue" 'RX1950 WLAN reset wiring is missing'
        require_fragment '#define RX1950_WLAN_NGCS4         S3C2410_GPA(15)' "$wlan_glue" 'RX1950 WLAN chip-select wiring is missing'
        require_fragment '#define RX1950_WLAN_CLKOUT1       S3C2410_GPH(10)' "$wlan_glue" 'RX1950 WLAN clock wiring is missing'
        require_fragment '#define RX1950_WLAN_IRQ_GPIO      S3C2410_GPG(8)' "$wlan_glue" 'RX1950 WLAN IRQ wiring is missing'
        require_fragment 'static bool gpa11_power;' "$wlan_glue" 'GPA11 compatibility mode is not explicit/opt-in'
        require_fragment 'if (gpa11_power)' "$wlan_glue" 'GPA11 must not be driven unconditionally'
        if grep -Eq 'GPC\(8\)|GPC\(9\)' "$wlan_glue"; then
            die 'WLAN glue must not repurpose the active GPC8/GPC9 LCD data pins'
        fi
        require_fragment "readonly ACX_COMMIT=\"${ACX_COMMIT}\"" "$build_script" 'ACX source is not pinned to the reviewed commit'
        require_fragment 'CONFIG_ACX_MAC80211_MEM=m' "$build_script" 'ACX slave-memory backend is not built'
        require_fragment 'CONFIG_ACX_MAC80211_PCI=n' "$build_script" 'unneeded ACX PCI transport is not disabled'
        require_fragment 'CONFIG_ACX_MAC80211_USB=n' "$build_script" 'unneeded ACX USB transport is not disabled'
        require_fragment 'kernel-modules.tar' "$build_script" 'kernel module bundle is not assembled'

        require_line 'BR2_PACKAGE_KMOD=y' "$rootfs_defconfig" 'kmod is missing from the engineering image'
        require_line 'BR2_PACKAGE_KMOD_TOOLS=y' "$rootfs_defconfig" 'kmod command-line tools are missing'
        require_line 'BR2_PACKAGE_IW=y' "$rootfs_defconfig" 'iw is missing from the engineering image'
        require_line 'BR2_PACKAGE_WPA_SUPPLICANT=y' "$rootfs_defconfig" 'wpa_supplicant is missing from the engineering image'
        require_line 'BR2_PACKAGE_CA_CERTIFICATES=y' "$rootfs_defconfig" 'CA certificates are missing for firmware retrieval'
        require_line 'BR2_PACKAGE_CURL=y' "$rootfs_defconfig" 'curl is missing for explicit firmware retrieval'
        require_line 'BR2_PACKAGE_HTOP=y' "$rootfs_defconfig" 'htop is missing from the engineering image'
        require_line 'BR2_PACKAGE_EVTEST=y' "$rootfs_defconfig" 'evtest is missing from the engineering image'
        require_line 'BR2_PACKAGE_I2C_TOOLS=y' "$rootfs_defconfig" 'i2c-tools are missing from the engineering image'
        require_line 'BR2_PACKAGE_LM_SENSORS=y' "$rootfs_defconfig" 'lm-sensors is missing from the engineering image'
        require_line 'BR2_PACKAGE_LM_SENSORS_SENSORS=y' "$rootfs_defconfig" 'the sensors utility is missing from the engineering image'
        require_line 'BR2_PACKAGE_STRACE=y' "$rootfs_defconfig" 'strace is missing from the engineering image'
        require_line 'BR2_TARGET_ROOTFS_EXT2_SIZE="64M"' "$rootfs_defconfig" 'rootfs seed size is not 64 MiB'

        require_fragment '/proc/self/mountinfo' "$grow_script" 'root grower still relies on the /dev/root alias'
        require_fragment '/sys/class/block/mmcblk0p2/dev' "$grow_script" 'root grower does not verify the mounted block device'
        require_fragment 'kernel-modules.tar' "$modules_script" 'module installer does not consume the FAT module bundle'
        require_fragment 'udhcpc -i usb0' "$usb_script" 'USB DHCP client is not started'
        require_fragment '192.168.7.2/24' "$usb_script" 'fixed USB recovery address was lost'
        require_fragment 'rx1950-usb-dhcp' "$dhcp_script" 'USB DHCP event handler is missing'
        require_fragment 'ip route replace default' "$dhcp_script" 'USB host default route handling is missing'
        require_fragment '/sys/devices/platform/s3c24xx-adc/s3c-hwmon/adc*_raw' "$sensors_script" 'RX1950 sensor helper does not use the verified Linux 6.2 raw-ADC path'
        require_fragment 'modprobe acx-mac80211' "$wlan_script" 'WLAN helper does not load the ACX driver first'
        require_fragment 'modprobe rx1950_acx' "$wlan_script" 'WLAN helper does not register RX1950 platform glue'
        require_fragment 'OPENBSD_URL=' "$firmware_script" 'ACX firmware retrieval helper is missing'
        require_fragment 'WLANGEN.BIN' "$firmware_script" 'ACX main firmware mapping is missing'
        require_fragment 'RADIO${suffix}.BIN' "$firmware_script" 'ACX radio firmware mapping is missing'
        require_fragment 'echo netdev > "$LED/trigger"' "$blue_script" 'Blue LED cannot be explicitly attached to WLAN activity'
        require_fragment 'echo none > "$LED/trigger"' "$blue_script" 'Blue LED cannot be returned to manual mode'
        require_fragment 'rx1950-wlan start independent' "$wlan_init" 'boot WLAN path is not independent of Blue/GPA11'
        require_line 'dest root /' "$opkg_conf" 'opkg root destination is missing'
        require_line 'lists_dir ext /var/lib/opkg/lists' "$opkg_conf" 'opkg list directory is missing'
        if grep -Eq '^[[:space:]]*src(/gz)?[[:space:]]' "$opkg_conf"; then
            die 'engineering opkg configuration must not point at an unverified binary feed'
        fi
        ;;

    kernel)
        config="${2:-${OUTPUT_DIR}/kernel.config}"
        require_line 'CONFIG_S3C_ADC=y' "$config" 'generated kernel dropped S3C ADC'
        require_line 'CONFIG_TOUCHSCREEN_S3C2410=y' "$config" 'generated kernel dropped the touchscreen driver'
        require_line 'CONFIG_BATTERY_S3C_ADC=y' "$config" 'generated kernel dropped the battery driver'
        require_line 'CONFIG_RTC_DRV_S3C=y' "$config" 'generated kernel dropped the RTC driver'
        require_line 'CONFIG_SND_SOC_SAMSUNG_RX1950_UDA1380=y' "$config" 'generated kernel dropped RX1950 audio'
        require_line 'CONFIG_DMADEVICES=y' "$config" 'generated kernel dropped DMAEngine'
        require_line 'CONFIG_S3C24XX_DMAC=y' "$config" 'generated kernel dropped the S3C24xx DMA controller driver'
        require_line 'CONFIG_MMC_S3C_PIO=y' "$config" 'generated kernel no longer pins SD to PIO'
        require_line '# CONFIG_MMC_S3C_DMA is not set' "$config" 'generated kernel unexpectedly enabled S3C MCI DMA'
        require_line 'CONFIG_I2C_CHARDEV=y' "$config" 'generated kernel dropped I2C userspace access'
        require_line 'CONFIG_HWMON=y' "$config" 'generated kernel dropped hwmon'
        require_line 'CONFIG_S3C_DEV_HWMON=y' "$config" 'generated kernel dropped the S3C hwmon platform device'
        require_line 'CONFIG_SENSORS_S3C=y' "$config" 'generated kernel dropped the S3C hwmon driver'
        require_line 'CONFIG_SENSORS_S3C_RAW=y' "$config" 'generated kernel dropped raw S3C ADC channels'
        require_line 'CONFIG_USB_G_NCM=y' "$config" 'generated kernel dropped CDC-NCM recovery networking'
        require_line 'CONFIG_MODULES=y' "$config" 'generated kernel dropped module support'
        require_line 'CONFIG_FW_LOADER=y' "$config" 'generated kernel dropped firmware loading'
        require_line 'CONFIG_CFG80211=y' "$config" 'generated kernel dropped cfg80211'
        require_line 'CONFIG_MAC80211=y' "$config" 'generated kernel dropped mac80211'
        require_line 'CONFIG_LEDS_TRIGGER_NETDEV=y' "$config" 'generated kernel dropped netdev LED trigger'
        test -s "${OUTPUT_DIR}/kernel-modules.tar" || die 'kernel WLAN module bundle is missing'
        tar -tf "${OUTPUT_DIR}/kernel-modules.tar" | grep -q '/acx-mac80211\.ko$' || die 'ACX100 module is missing from module bundle'
        tar -tf "${OUTPUT_DIR}/kernel-modules.tar" | grep -q '/rx1950_acx\.ko$' || die 'RX1950 platform module is missing from module bundle'
        ;;

    rootfs)
        config="${2:-${OUTPUT_DIR}/buildroot.config}"
        require_line 'BR2_PACKAGE_KMOD=y' "$config" 'generated rootfs dropped kmod'
        require_line 'BR2_PACKAGE_KMOD_TOOLS=y' "$config" 'generated rootfs dropped kmod tools'
        require_line 'BR2_PACKAGE_IW=y' "$config" 'generated rootfs dropped iw'
        require_line 'BR2_PACKAGE_WPA_SUPPLICANT=y' "$config" 'generated rootfs dropped wpa_supplicant'
        require_line 'BR2_PACKAGE_CURL=y' "$config" 'generated rootfs dropped curl'
        require_line 'BR2_PACKAGE_CA_CERTIFICATES=y' "$config" 'generated rootfs dropped CA certificates'
        require_line 'BR2_PACKAGE_HTOP=y' "$config" 'generated rootfs dropped htop'
        require_line 'BR2_PACKAGE_EVTEST=y' "$config" 'generated rootfs dropped evtest'
        require_line 'BR2_PACKAGE_I2C_TOOLS=y' "$config" 'generated rootfs dropped i2c-tools'
        require_line 'BR2_PACKAGE_LM_SENSORS=y' "$config" 'generated rootfs dropped lm-sensors'
        require_line 'BR2_PACKAGE_LM_SENSORS_SENSORS=y' "$config" 'generated rootfs dropped sensors'
        require_line 'BR2_PACKAGE_STRACE=y' "$config" 'generated rootfs dropped strace'
        require_line 'BR2_TARGET_ROOTFS_EXT2_SIZE="64M"' "$config" 'generated rootfs seed is not 64 MiB'
        ;;

    image)
        command -v debugfs >/dev/null 2>&1 || die 'debugfs is required for peripheral image validation'
        rootfs="${OUTPUT_DIR}/rootfs.ext2"
        test -s "$rootfs" || die 'rootfs.ext2 is missing'
        test -s "${OUTPUT_DIR}/kernel-modules.tar" || die 'sealed image lost kernel module bundle'

        for path in /usr/bin/htop /usr/bin/evtest /usr/sbin/i2cdetect /usr/bin/sensors \
                    /usr/bin/strace /usr/sbin/iw /usr/bin/curl /usr/bin/kmod \
                    /usr/sbin/rx1950-sensors /usr/sbin/rx1950-wlan \
                    /usr/sbin/rx1950-wlan-firmware /usr/sbin/rx1950-blue \
                    /etc/opkg/opkg.conf /sbin/udhcpc \
                    /usr/share/udhcpc/rx1950-usb.script /etc/init.d/S05grow-root \
                    /etc/init.d/S10kernel-modules /etc/init.d/S35usb-gadget \
                    /etc/init.d/S40wlan; do
            rootfs_has "$rootfs" "$path" || die "sealed rootfs is missing ${path}"
        done

        # Proprietary TI ACX firmware must never be redistributed by this image.
        if rootfs_has "$rootfs" /lib/firmware/WLANGEN.BIN; then
            die 'sealed rootfs illegally bundles WLANGEN.BIN'
        fi
        ;;

    *)
        die 'usage: validate-peripherals.sh {source|kernel [config]|rootfs [config]|image}'
        ;;
esac

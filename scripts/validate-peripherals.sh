#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly OUTPUT_DIR="${ROOT_DIR}/output"
# shellcheck source=sources.lock.sh
source "${ROOT_DIR}/scripts/sources.lock.sh"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
require_line() { grep -Fqx "$1" "$2" || die "$3"; }
require_fragment() { grep -Fq "$1" "$2" || die "$3"; }
rootfs_has() { debugfs -R "stat $2" "$1" 2>&1 | grep -q 'Inode:'; }

case "${1:-source}" in
source)
    kcfg="${ROOT_DIR}/kernel/rx1950_defconfig"
    rcfg="${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
    busybox_fragment="${ROOT_DIR}/buildroot/external/rx1950/configs/busybox.fragment"
    grow="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/init.d/S05grow-root"
    mods="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/init.d/S10kernel-modules"
    zram="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/init.d/S20zram"
    usb="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/init.d/S35usb-gadget"
    time_sync="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/init.d/S38time-sync"
    wlan_init="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/init.d/S40wlan"
    xserver="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/init.d/S48xserver"
    dhcp="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/share/udhcpc/rx1950-usb.script"
    sensors="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/sbin/rx1950-sensors"
    wlan="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/sbin/rx1950-wlan"
    fw="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/sbin/rx1950-wlan-firmware"
    blue="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/sbin/rx1950-blue"
    glue="${ROOT_DIR}/kernel/modules/rx1950-acx/rx1950_acx.c"
    acx_patch="${ROOT_DIR}/kernel/acx-patches/0001-mem-ack-irqs-before-deferred-work.patch"
    acx_scan_patch="${ROOT_DIR}/kernel/acx-patches/0002-scan-cancel-before-interface-stop.patch"
    build="${ROOT_DIR}/scripts/build.sh"
    sources_lock="${ROOT_DIR}/scripts/sources.lock.sh"
    opkg="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/opkg/opkg.conf"
    hwmon="${ROOT_DIR}/kernel/patches/0010-rx1950-enable-hwmon.patch"
    audio_dma="${ROOT_DIR}/kernel/patches/0011-rx1950-register-audio-dma.patch"
    blue_patch="${ROOT_DIR}/kernel/patches/0011-rx1950-decouple-blue-led.patch"
    unsafe_mmc="${ROOT_DIR}/kernel/patches/0011-s3cmci-fix-gpiod-return-handling.patch"
    nand_protect="${ROOT_DIR}/kernel/patches/0012-rx1950-protect-internal-nand.patch"

    for req in \
        CONFIG_S3C_ADC=y CONFIG_TOUCHSCREEN_S3C2410=y CONFIG_BATTERY_S3C_ADC=y \
        CONFIG_RTC_DRV_S3C=y CONFIG_SND_SOC_SAMSUNG_RX1950_UDA1380=y \
        CONFIG_MMC_S3C_PIO=y CONFIG_I2C_CHARDEV=y CONFIG_HWMON=y \
        CONFIG_SENSORS_S3C=y CONFIG_SENSORS_S3C_RAW=y CONFIG_MODULES=y \
        CONFIG_FW_LOADER=y CONFIG_CFG80211=y CONFIG_MAC80211=y \
        CONFIG_SWAP=y CONFIG_ZRAM=y CONFIG_CRYPTO_LZO=y \
        CONFIG_ZRAM_DEF_COMP_LZORLE=y \
        CONFIG_LEDS_TRIGGERS=y CONFIG_LEDS_TRIGGER_NETDEV=y; do
        require_line "$req" "$kcfg" "RX1950 kernel requirement missing: $req"
    done
    require_line '# CONFIG_MMC_S3C_DMA is not set' "$kcfg" 'RX1950 SD DMA must remain disabled'
    require_line '# CONFIG_MTD_BLOCK is not set' "$kcfg" 'internal NAND block access must remain disabled'
    require_line 'CONFIG_EXTRA_FIRMWARE="regulatory.db regulatory.db.p7s"' "$kcfg" 'regulatory database is not embedded in the kernel'
    require_line 'CONFIG_EXTRA_FIRMWARE_DIR="firmware"' "$kcfg" 'kernel firmware source directory changed'

    require_fragment 'depends on !ARCH_MULTIPLATFORM || ARCH_S3C24XX' "${ROOT_DIR}/kernel/patches/0006-s3c24xx-restore-adc-multiplatform.patch" 'S3C24xx ADC compatibility patch missing'
    require_fragment 'nr_irqs - S3C2410_IRQSUB(0)' "${ROOT_DIR}/kernel/patches/0007-s3c24xx-fix-static-irq-domain-size.patch" 'S3C24xx IRQ-domain fix missing'
    require_fragment 's3c_rtc_driver_ids' "${ROOT_DIR}/kernel/patches/0008-s3c-rtc-restore-platform-data-matching.patch" 'legacy RTC matching patch missing'
    require_fragment '{"Right ADC", NULL, "Right PGA"}' "${ROOT_DIR}/kernel/patches/0009-uda1380-fix-right-adc-dapm-route.patch" 'UDA1380 DAPM fix missing'
    require_fragment 'select S3C_DEV_HWMON' "$hwmon" 'RX1950 hwmon selection missing'
    require_fragment 's3c_hwmon_set_platdata(&rx1950_hwmon_pdata);' "$hwmon" 'RX1950 hwmon platform data missing'
    require_fragment '.mult = 4235' "$hwmon" 'RX1950 voltage scaling missing'
    require_fragment 'WARN_ON(platform_device_register(&s3c_device_hwmon));' "$hwmon" 'hwmon is not isolated from boot-critical devices'
    require_fragment 'WARN_ON(platform_device_register(&s3c2410_device_dma));' "$audio_dma" 'audio DMA provider is not registered'
    if grep -Fq '&s3c2410_device_dma,' "$hwmon"; then die 'experimental DMA device must not enter the RX1950 boot path'; fi
    if grep -Fq '&s3c_device_hwmon,' "$hwmon"; then die 'optional hwmon must not enter the RX1950 boot-critical device array'; fi
    [[ ! -e "$unsafe_mmc" ]] || die 'unsafe S3CMCI GPIO patch must remain reverted'
    [[ "$(grep -Fc '.mask_flags = MTD_WRITEABLE,' "$nand_protect")" -eq 2 ]] ||
        die 'all writable RX1950 NAND data partitions must be forced read-only'

    [[ ! -e "$blue_patch" ]] || die 'obsolete Blue LED decoupling patch must remain removed'
    require_fragment '#define RX1950_WLAN_BASE          0x20000000' "$glue" 'ACX MMIO resource missing'
    require_fragment '#define RX1950_WLAN_RESET         S3C2410_GPA(14)' "$glue" 'WLAN reset wiring missing'
    require_fragment '#define RX1950_WLAN_NGCS4         S3C2410_GPA(15)' "$glue" 'WLAN chip-select wiring missing'
    require_fragment '#define RX1950_WLAN_CLKOUT1       S3C2410_GPH(10)' "$glue" 'WLAN clock wiring missing'
    require_fragment '#define RX1950_WLAN_IRQ_GPIO      S3C2410_GPG(8)' "$glue" 'WLAN IRQ wiring missing'
    require_fragment '#define RX1950_WLAN_AUX1          S3C2410_GPC(8)' "$glue" 'historical RX1950 WLAN GPC8 line missing'
    require_fragment '#define RX1950_WLAN_AUX2          S3C2410_GPC(9)' "$glue" 'historical RX1950 WLAN GPC9 line missing'
    require_fragment 'static bool gpa11_power = true;' "$glue" 'historical GPA11 WLAN power must be the default'
    require_fragment 'led_trigger_register_simple("rx1950-acx-mem"' "$glue" 'GPA11 is not owned through the mainline Blue LED trigger'
    require_fragment 'led_trigger_event(rx1950_wlan_power_trigger, LED_FULL);' "$glue" 'GPA11 WLAN power is not asserted through the LED subsystem'
    require_fragment 'gpio_direction_output(RX1950_WLAN_AUX1, 1)' "$glue" 'historical GPC8 WLAN state is not asserted'
    require_fragment 'gpio_direction_output(RX1950_WLAN_AUX2, 1)' "$glue" 'historical GPC9 WLAN state is not asserted'

    require_fragment 'adev->irq_reason |= deferred;' "$acx_patch" 'ACX deferred MEM IRQ causes are not latched in hard IRQ'
    require_fragment 'irqmasked & ~HOST_INT_CMD_COMPLETE' "$acx_patch" 'ACX command completion can be consumed before its poller'
    require_fragment '.cancel_hw_scan' "$acx_scan_patch" 'ACX scan cancellation callback is missing'
    require_fragment 'test_and_clear_bit(ACX_FLAG_SCANNING' "$acx_scan_patch" 'ACX scan completion is not serialized'
    require_fragment "readonly ACX_COMMIT=\"${ACX_COMMIT}\"" "$sources_lock" 'ACX source commit is not pinned'
    require_fragment 'source "${ROOT_DIR}/scripts/sources.lock.sh"' "$build" 'build does not consume the pinned source lock'
    require_fragment "'=http,https'" "$build" 'legacy ACX firmware redirect cannot reach HTTPS'
    require_fragment 'kernel/acx-patches/*.patch' "$build" 'local ACX patch set is not applied'
    require_fragment 'CONFIG_ACX_MAC80211_MEM=m' "$build" 'ACX memory transport not built'
    require_fragment 'CONFIG_ACX_MAC80211_PCI=n' "$build" 'unneeded ACX PCI transport enabled'
    require_fragment 'CONFIG_ACX_MAC80211_USB=n' "$build" 'unneeded ACX USB transport enabled'
    require_fragment 'kernel-modules.tar' "$build" 'WLAN module bundle not assembled'

    for req in \
        BR2_PACKAGE_KMOD=y BR2_PACKAGE_KMOD_TOOLS=y BR2_PACKAGE_IW=y \
        BR2_PACKAGE_WPA_SUPPLICANT=y BR2_PACKAGE_WPA_SUPPLICANT_NL80211=y \
        BR2_PACKAGE_WPA_SUPPLICANT_PASSPHRASE=y BR2_PACKAGE_CA_CERTIFICATES=y \
        BR2_PACKAGE_WIRELESS_REGDB=y \
        BR2_PACKAGE_OPENSSL=y BR2_PACKAGE_LIBCURL=y BR2_PACKAGE_LIBCURL_CURL=y \
        BR2_PACKAGE_LIBCURL_OPENSSL=y BR2_PACKAGE_HTOP=y BR2_PACKAGE_EVTEST=y \
        BR2_PACKAGE_I2C_TOOLS=y BR2_PACKAGE_LM_SENSORS=y \
        BR2_PACKAGE_LM_SENSORS_SENSORS=y BR2_PACKAGE_STRACE=y \
        BR2_TARGET_TZ_INFO=y BR2_PACKAGE_XSERVER_XORG_SERVER_MODULAR=y \
        BR2_PACKAGE_XDRIVER_XF86_VIDEO_FBDEV=y \
        BR2_PACKAGE_XDRIVER_XF86_INPUT_EVDEV=y \
        BR2_PACKAGE_ALSA_UTILS_ALSACTL=y BR2_PACKAGE_ALSA_UTILS_AMIXER=y \
        BR2_PACKAGE_ALSA_UTILS_APLAY=y BR2_PACKAGE_ALSA_UTILS_SPEAKER_TEST=y \
        BR2_PACKAGE_XAPP_XINPUT=y BR2_PACKAGE_XAPP_XINPUT_CALIBRATOR=y \
        BR2_PACKAGE_MATCHBOX_COMMON=y BR2_PACKAGE_MATCHBOX_COMMON_PDA=y \
        BR2_PACKAGE_GPE_CONF_RX1950=y BR2_PACKAGE_TRIGGERHAPPY=y \
        BR2_PACKAGE_XAPP_XCALC=y BR2_PACKAGE_XAPP_XSET=y BR2_PACKAGE_LEAFPAD=y \
        BR2_PACKAGE_DIALOG=y BR2_PACKAGE_XTERM=y; do
        require_line "$req" "$rcfg" "RX1950 rootfs requirement missing: $req"
    done
    require_line 'BR2_TARGET_GENERIC_ROOT_PASSWD=""' "$rcfg" 'RX1950 rootfs does not configure a blank root password'
    require_line 'CONFIG_NTPD=y' "$busybox_fragment" 'BusyBox NTP client is disabled'
    require_line 'CONFIG_TIMEOUT=y' "$busybox_fragment" 'BusyBox timeout is required for bounded radio health checks'
    require_line 'BR2_TARGET_ROOTFS_EXT2_SIZE="512M"' "$rcfg" 'rootfs seed size is not 512 MiB'
    if grep -Fq 'BR2_PACKAGE_CURL=y' "$rcfg"; then die 'legacy Buildroot BR2_PACKAGE_CURL must not be used'; fi

    require_fragment '/proc/self/mountinfo' "$grow" 'root grower still relies on /dev/root alias'
    require_fragment '/sys/class/block/mmcblk0p2/dev' "$grow" 'root grower does not verify root device identity'
    require_fragment 'kernel-modules.tar' "$mods" 'module installer does not consume FAT module bundle'
    require_fragment 'echo 12M > /sys/block/zram0/disksize' "$zram" 'zram swap size is not bounded to 12 MiB'
    require_fragment 'echo lzo-rle > /sys/block/zram0/comp_algorithm' "$zram" 'zram does not use the ARM9-friendly lzo-rle compressor'
    require_fragment 'ptmxmode=0666' "${ROOT_DIR}/buildroot/external/rx1950/board/hp_rx1950/fstab" 'devpts does not permit PTY allocation'
    require_fragment "sset 'Master Playback Switch' on" "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/init.d/S30alsa" 'UDA1380 master output is not unmuted at boot'
    require_fragment 'rx1950-usb-dhcp' "$usb" 'bounded USB DHCP supervisor is not started'
    require_fragment '192.168.7.2/24' "$usb" 'fixed USB recovery address lost'
    require_fragment 'ip route replace default' "$dhcp" 'USB default route handling missing'
    require_fragment 'rx1950-time-sync' "$time_sync" 'boot-time NTP synchronization is not started'
    require_fragment '/sys/devices/platform/s3c24xx-adc/s3c-hwmon/adc*_raw' "$sensors" 'sensor helper does not use verified Linux 6.2 ADC path'
    require_fragment 'modprobe acx-mac80211' "$wlan" 'WLAN helper does not load ACX driver first'
    require_fragment 'modprobe acx-mac80211 watchdog=1' "$wlan" 'ACX scan watchdog is not enabled'
    if grep -Fq 'timeout 20 iw dev' "$wlan"; then die 'boot-time WLAN scan must not trigger ACX recovery'; fi
    require_fragment 'iw reg set "$REGDOMAIN"' "$wlan" 'WLAN regulatory domain is not applied before scanning'
    require_fragment 'modprobe rx1950_acx' "$wlan" 'WLAN helper does not load RX1950 glue'
    require_fragment 'no-gpa11-power' "$wlan" 'WLAN helper lacks the explicit no-GPA11 diagnostic mode'
    require_fragment 'OPENBSD_URL=' "$fw" 'ACX firmware fetch helper missing'
    require_fragment 'WLANGEN.BIN' "$fw" 'ACX main firmware mapping missing'
    require_fragment "tr 'A-F' 'a-f'" "$fw" 'ACX radio firmware hex suffix is not normalized to driver case'
    require_fragment 'shared_power_active' "$blue" 'Blue helper does not protect the shared GPA11 WLAN power line'
    require_fragment 'echo netdev > "$LED/trigger"' "$blue" 'Blue LED cannot use explicit WLAN trigger in diagnostic independent mode'
    require_fragment 'echo none > "$LED/trigger"' "$blue" 'Blue LED cannot return to manual mode in diagnostic independent mode'
    require_fragment 'rx1950-wlan start historical' "$wlan_init" 'boot WLAN path does not follow the historical RX1950 wiring'
    require_fragment 'Xorg :0 -config /etc/X11/xorg.conf' "$xserver" 'Xorg framebuffer server is not started'
    require_fragment 'mb-applet-menu-launcher' "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/init.d/S50matchbox" 'Matchbox application menu is not started'
    require_fragment 'MATCHBOX_THEME' "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/init.d/S50matchbox" 'persistent Matchbox theme selection is missing'
    require_fragment 'exec gpe-conf "$@"' "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/bin/rx1950-settings-launcher" 'settings launcher does not open the graphical control center'
    require_fragment 'exec gpe-conf wifi' "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/bin/rx1950-wifi-launcher" 'Wi-Fi launcher does not open the native graphical applet'
    require_fragment 'key-reload)' "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/sbin/rx1950-control" 'button assignments are not reloaded atomically'
    require_fragment 'user root' "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/default/triggerhappy" 'hardware button actions cannot control the root-owned PDA session'
    if grep -Eq '^[[:space:]]*matchbox-keyboard[[:space:]]*&' "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/init.d/S50matchbox"; then
        die 'on-screen keyboard must not occupy the desktop at boot'
    fi
    require_fragment 'udhcpc -i "$ifname" -p "$DHCP_PIDFILE" -n -q' "$wlan" 'WLAN DHCP is not bounded'
    require_fragment 'wpa_supplicant -B -D wext' "$wlan" 'WLAN must use the ACX100-compatible WEXT backend'
    for gui_script in \
        "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/init.d/S50matchbox" \
        "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/bin/mb-applet-xterm-wrapper.sh" \
        "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/bin/rx1950-keyboard" \
        "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/bin/rx1950-launch" \
        "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/bin/rx1950-settings-launcher" \
        "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/bin/rx1950-wifi-launcher" \
        "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/sbin/rx1950-control" \
        "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/sbin/rx1950-settings" \
        "${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/usr/sbin/rx1950-wifi-ui"; do
        test -s "$gui_script" || die "GUI script is missing: $gui_script"
        sh -n "$gui_script" || die "GUI script has invalid shell syntax: $gui_script"
    done
    require_line 'dest root /' "$opkg" 'opkg root destination missing'
    require_line 'option lists_dir /var/lib/opkg/lists' "$opkg" 'opkg list directory missing'
    if grep -Eq '^[[:space:]]*src(/gz)?[[:space:]]' "$opkg"; then die 'engineering opkg config must not use an unverified binary feed'; fi
    ;;

kernel)
    cfg="${2:-${OUTPUT_DIR}/kernel.config}"
    for req in \
        CONFIG_S3C_ADC=y CONFIG_TOUCHSCREEN_S3C2410=y CONFIG_BATTERY_S3C_ADC=y \
        CONFIG_RTC_DRV_S3C=y CONFIG_SND_SOC_SAMSUNG_RX1950_UDA1380=y \
        CONFIG_DMADEVICES=y CONFIG_S3C24XX_DMAC=y CONFIG_MMC_S3C_PIO=y \
        CONFIG_SWAP=y CONFIG_ZRAM=y CONFIG_CRYPTO_LZO=y \
        CONFIG_ZRAM_DEF_COMP_LZORLE=y \
        CONFIG_I2C_CHARDEV=y CONFIG_HWMON=y CONFIG_S3C_DEV_HWMON=y \
        CONFIG_SENSORS_S3C=y CONFIG_SENSORS_S3C_RAW=y CONFIG_USB_G_NCM=y \
        CONFIG_MODULES=y CONFIG_FW_LOADER=y CONFIG_CFG80211=y CONFIG_MAC80211=y \
        CONFIG_LEDS_TRIGGERS=y CONFIG_LEDS_TRIGGER_NETDEV=y; do
        require_line "$req" "$cfg" "generated kernel dropped: $req"
    done
    require_line '# CONFIG_MMC_S3C_DMA is not set' "$cfg" 'generated kernel unexpectedly enabled S3C MCI DMA'
    require_line '# CONFIG_MTD_BLOCK is not set' "$cfg" 'generated kernel exposes internal NAND as a block device'
    require_line 'CONFIG_EXTRA_FIRMWARE="regulatory.db regulatory.db.p7s"' "$cfg" 'generated kernel does not embed regulatory.db'
    require_line 'CONFIG_EXTRA_FIRMWARE_DIR="firmware"' "$cfg" 'generated kernel firmware directory changed'
    test -s "${OUTPUT_DIR}/kernel-modules.tar" || die 'kernel WLAN module bundle missing'
    tar -tf "${OUTPUT_DIR}/kernel-modules.tar" | grep -q '/acx-mac80211\.ko$' || die 'ACX100 module missing from bundle'
    tar -tf "${OUTPUT_DIR}/kernel-modules.tar" | grep -q '/rx1950_acx\.ko$' || die 'RX1950 WLAN glue missing from bundle'
    ;;

rootfs)
    cfg="${2:-${OUTPUT_DIR}/buildroot.config}"
    for req in \
        BR2_PACKAGE_KMOD=y BR2_PACKAGE_KMOD_TOOLS=y BR2_PACKAGE_IW=y \
        BR2_PACKAGE_WPA_SUPPLICANT=y BR2_PACKAGE_WPA_SUPPLICANT_NL80211=y \
        BR2_PACKAGE_WPA_SUPPLICANT_PASSPHRASE=y BR2_PACKAGE_CA_CERTIFICATES=y \
        BR2_PACKAGE_WIRELESS_REGDB=y \
        BR2_PACKAGE_OPENSSL=y BR2_PACKAGE_LIBCURL=y BR2_PACKAGE_LIBCURL_CURL=y \
        BR2_PACKAGE_LIBCURL_OPENSSL=y BR2_PACKAGE_HTOP=y BR2_PACKAGE_EVTEST=y \
        BR2_PACKAGE_I2C_TOOLS=y BR2_PACKAGE_LM_SENSORS=y \
        BR2_PACKAGE_LM_SENSORS_SENSORS=y BR2_PACKAGE_STRACE=y \
        BR2_TARGET_TZ_INFO=y BR2_PACKAGE_TZDATA=y \
        BR2_PACKAGE_XSERVER_XORG_SERVER_MODULAR=y \
        BR2_PACKAGE_XDRIVER_XF86_VIDEO_FBDEV=y \
        BR2_PACKAGE_XDRIVER_XF86_INPUT_EVDEV=y \
        BR2_PACKAGE_ALSA_UTILS_ALSACTL=y BR2_PACKAGE_ALSA_UTILS_AMIXER=y \
        BR2_PACKAGE_ALSA_UTILS_APLAY=y BR2_PACKAGE_ALSA_UTILS_SPEAKER_TEST=y \
        BR2_PACKAGE_XAPP_XINPUT=y BR2_PACKAGE_XAPP_XINPUT_CALIBRATOR=y \
        BR2_PACKAGE_GPE_CONF_RX1950=y BR2_PACKAGE_TRIGGERHAPPY=y \
        BR2_PACKAGE_XAPP_XCALC=y BR2_PACKAGE_XAPP_XSET=y BR2_PACKAGE_LEAFPAD=y; do
        require_line "$req" "$cfg" "generated rootfs dropped: $req"
    done
    require_line 'BR2_TARGET_GENERIC_ROOT_PASSWD=""' "$cfg" 'generated rootfs does not use a blank root password'
    require_line 'BR2_TARGET_ROOTFS_EXT2_SIZE="512M"' "$cfg" 'generated rootfs seed is not 512 MiB'
    ;;

image)
    command -v debugfs >/dev/null 2>&1 || die 'debugfs required for image validation'
    rootfs="${OUTPUT_DIR}/rootfs.ext2"
    test -s "$rootfs" || die 'rootfs.ext2 missing'
    test -s "${OUTPUT_DIR}/kernel-modules.tar" || die 'sealed image lost kernel module bundle'
    for path in \
        /usr/bin/htop /usr/bin/evtest /usr/sbin/i2cdetect /usr/bin/sensors \
        /usr/bin/strace /usr/sbin/iw /usr/bin/curl /usr/bin/kmod /usr/sbin/wpa_supplicant \
        /usr/sbin/wpa_passphrase /usr/sbin/ntpd /usr/sbin/rx1950-time-sync \
        /usr/sbin/rx1950-usb-dhcp /usr/bin/amixer /usr/bin/arecord \
        /usr/sbin/alsactl /usr/bin/speaker-test /usr/bin/xinput \
        /usr/bin/xinput_calibrator \
        /usr/bin/gpe-conf /usr/sbin/rx1950-control /usr/sbin/thd \
        /usr/bin/xcalc /usr/bin/xset /usr/bin/leafpad /usr/bin/rx1950-launch \
        /etc/triggerhappy/triggers.d/rx1950.conf /etc/default/triggerhappy \
        /etc/default/rx1950-power /etc/default/rx1950-ui \
        /usr/share/applications/rx1950-calculator.desktop \
        /usr/share/applications/rx1950-editor.desktop \
        /usr/sbin/rx1950-timezone /usr/sbin/rx1950-sensors /usr/sbin/rx1950-wlan \
        /usr/sbin/rx1950-wlan-firmware /usr/sbin/rx1950-blue /etc/default/dropbear \
        /etc/ssl/certs/ca-certificates.crt /etc/opkg/opkg.conf /sbin/udhcpc \
        /usr/share/udhcpc/rx1950-usb.script /etc/init.d/S05grow-root \
        /etc/init.d/S02clock-sanity /etc/init.d/S10kernel-modules \
        /etc/init.d/S20zram /etc/init.d/S30alsa /etc/init.d/S35usb-gadget \
        /etc/init.d/S38time-sync /etc/init.d/S40wlan /etc/init.d/S48xserver \
        /usr/bin/Xorg /usr/lib/xorg/modules/drivers/fbdev_drv.so \
        /usr/lib/xorg/modules/input/evdev_drv.so /etc/X11/xorg.conf \
        /lib/firmware/regulatory.db /lib/firmware/regulatory.db.p7s \
        /usr/lib/rx1950/build-epoch /usr/lib/rx1950/build-date-utc \
        /lib/firmware/WLANGEN.BIN \
        /lib/firmware/RADIO0d.BIN /lib/firmware/RADIO11.BIN; do
        rootfs_has "$rootfs" "$path" || die "sealed rootfs missing $path"
    done
    ;;

*) die 'usage: validate-peripherals.sh {source|kernel [config]|rootfs [config]|image}' ;;
esac

#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Validate the rx1950 hardware/runtime contract without encoding device numbers
# or UI choices that are intentionally configurable at runtime.
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly OUTPUT_DIR="${ROOT_DIR}/output"
readonly RCFG="${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
readonly KCFG="${ROOT_DIR}/kernel/rx1950_defconfig"
readonly OVERLAY="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
require_line() { grep -Fqx -- "$1" "$2" || die "${3:-missing '$1' in $2}"; }
require_fragment() { grep -Fq -- "$1" "$2" || die "${3:-missing '$1' in $2}"; }
forbid_fragment() { ! grep -Fq -- "$1" "$2" || die "${3:-forbidden '$1' in $2}"; }
require_file() { test -s "$1" || die "missing file: $1"; }
require_exec() { test -x "$1" || die "not executable: $1"; }

validate_kernel_config() {
    local cfg="$1" req
    for req in \
        CONFIG_ARCH_MULTI_V4T=y CONFIG_CPU_S3C2442=y CONFIG_MACH_RX1950=y \
        CONFIG_AEABI=y CONFIG_KUSER_HELPERS=y CONFIG_HZ_100=y \
        CONFIG_DEVTMPFS=y CONFIG_DEVTMPFS_MOUNT=y CONFIG_INPUT_EVDEV=y \
        CONFIG_KEYBOARD_GPIO=y CONFIG_TOUCHSCREEN_S3C2410=y \
        CONFIG_FB_S3C2410=y CONFIG_FRAMEBUFFER_CONSOLE=y \
        CONFIG_BACKLIGHT_CLASS_DEVICE=y CONFIG_BACKLIGHT_PWM=y CONFIG_PWM_SAMSUNG=y \
        CONFIG_POWER_SUPPLY=y CONFIG_BATTERY_S3C_ADC=y \
        CONFIG_I2C_CHARDEV=y CONFIG_I2C_S3C2410=y CONFIG_HWMON=y \
        CONFIG_SENSORS_S3C=y CONFIG_SENSORS_S3C_RAW=y \
        CONFIG_SND_SOC_SAMSUNG_RX1950_UDA1380=y \
        CONFIG_MMC=y CONFIG_MMC_BLOCK=y CONFIG_MMC_S3C=y CONFIG_MMC_S3C_PIO=y \
        CONFIG_DMADEVICES=y CONFIG_S3C24XX_DMAC=y \
        CONFIG_SWAP=y CONFIG_ZRAM=y CONFIG_CRYPTO_LZO=y CONFIG_ZRAM_DEF_COMP_LZORLE=y \
        CONFIG_CFG80211=y CONFIG_CFG80211_WEXT=y CONFIG_MAC80211=y \
        CONFIG_USB_G_NCM=y CONFIG_LEDS_TRIGGER_NETDEV=y CONFIG_RTC_DRV_S3C=y; do
        require_line "$req" "$cfg" "kernel contract dropped: $req"
    done
    for req in \
        '# CONFIG_ARCH_MULTI_V7 is not set' '# CONFIG_OABI_COMPAT is not set' \
        '# CONFIG_MMC_S3C_DMA is not set' '# CONFIG_MTD_BLOCK is not set' \
        '# CONFIG_IP_PNP is not set' '# CONFIG_IPV6 is not set' \
        '# CONFIG_EXT2_FS is not set' '# CONFIG_MSDOS_FS is not set' \
        '# CONFIG_SERIAL_SAMSUNG_CONSOLE is not set' '# CONFIG_DEBUG_KERNEL is not set'; do
        require_line "$req" "$cfg" "kernel optimization/safety contract dropped: $req"
    done
    require_line 'CONFIG_LOG_BUF_SHIFT=14' "$cfg" 'kernel log buffer is no longer bounded'
    require_line 'CONFIG_CMDLINE_FROM_BOOTLOADER=y' "$cfg" 'normal boot must accept HaRET command line'
    require_line '# CONFIG_CMDLINE_FORCE is not set' "$cfg" 'normal kernel must not force SD-root command line'
    require_line 'CONFIG_EXTRA_FIRMWARE="regulatory.db regulatory.db.p7s"' "$cfg" 'wireless regulatory database is not embedded'
}

validate_rootfs_config() {
    local cfg="$1" req
    for req in \
        BR2_arm920t=y BR2_ARM_EABI=y BR2_SOFT_FLOAT=y BR2_ARM_INSTRUCTIONS_ARM=y \
        BR2_TOOLCHAIN_BUILDROOT_MUSL=y BR2_REPRODUCIBLE=y BR2_CCACHE=y \
        BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV=y \
        BR2_PACKAGE_KMOD=y BR2_PACKAGE_IW=y BR2_PACKAGE_WPA_SUPPLICANT=y \
        BR2_PACKAGE_WPA_SUPPLICANT_PASSPHRASE=y BR2_PACKAGE_WIRELESS_REGDB=y \
        BR2_PACKAGE_CA_CERTIFICATES=y BR2_PACKAGE_OPENSSL=y BR2_PACKAGE_LIBCURL=y \
        BR2_PACKAGE_ALSA_UTILS=y BR2_PACKAGE_XORG7=y \
        BR2_PACKAGE_XSERVER_XORG_SERVER_MODULAR=y BR2_PACKAGE_XDRIVER_XF86_VIDEO_FBDEV=y \
        BR2_PACKAGE_XDRIVER_XF86_INPUT_EVDEV=y BR2_PACKAGE_XAPP_XINPUT=y \
        BR2_PACKAGE_XAPP_XINPUT_CALIBRATOR=y BR2_PACKAGE_LIBSHA1=y \
        BR2_PACKAGE_JWM=y BR2_PACKAGE_MATCHBOX=y BR2_PACKAGE_MATCHBOX_KEYBOARD=y \
        BR2_PACKAGE_RX1950_SETTINGS=y BR2_PACKAGE_TRIGGERHAPPY=y \
        BR2_PACKAGE_PCMANFM=y BR2_PACKAGE_LEAFPAD=y BR2_PACKAGE_DILLO=y \
        BR2_PACKAGE_XAPP_XCALC=y BR2_PACKAGE_XAPP_XSET=y BR2_PACKAGE_XTERM=y \
        BR2_TARGET_TZ_INFO=y; do
        require_line "$req" "$cfg" "rootfs contract dropped: $req"
    done
    require_line '# BR2_PACKAGE_EUDEV_MODULE_LOADING is not set' "$cfg" 'unused eudev module loader enabled'
    require_line '# BR2_PACKAGE_EUDEV_RULES_GEN is not set' "$cfg" 'unused eudev rule generation enabled'
    require_line '# BR2_PACKAGE_EUDEV_ENABLE_HWDB is not set' "$cfg" 'unused eudev hwdb enabled'
    require_line 'BR2_TARGET_ROOTFS_EXT2_SIZE="128M"' "$cfg" 'rootfs seed size changed unexpectedly'
    if grep -Fqx -- 'BR2_PACKAGE_DIALOG=y' "$cfg"; then die 'dialog terminal UI must not be in the base image'; fi
    if grep -Fqx -- 'BR2_PACKAGE_WIRELESS_TOOLS=y' "$cfg"; then die 'legacy wireless-tools must not be in the base image'; fi
    if grep -Fqx -- 'BR2_PACKAGE_XAPP_XEDIT=y' "$cfg"; then die 'xedit was replaced by Leafpad'; fi
    if grep -Eq '^BR2_PACKAGE_MATCHBOX_(COMMON|DESKTOP|PANEL)=y$' "$cfg"; then die 'unused Matchbox desktop components enabled'; fi
    return 0
}

validate_source_runtime() {
    local jwm="${OVERLAY}/etc/jwm/system.jwmrc"
    local xserver="${OVERLAY}/etc/init.d/S48xserver"
    local xgen="${OVERLAY}/usr/sbin/rx1950-xorg-config"
    local wlan="${OVERLAY}/usr/sbin/rx1950-wlan"
    local control="${OVERLAY}/usr/sbin/rx1950-control"
    local keyboard="${OVERLAY}/usr/bin/rx1950-keyboard"
    local menu="${OVERLAY}/usr/bin/rx1950-jwm-app-menu"
    local panel="${OVERLAY}/usr/bin/rx1950-jwm-panel-config"
    local post="${ROOT_DIR}/buildroot/external/rx1950/board/hp_rx1950/post-build.sh"
    local f obsolete

    for f in "$xgen" "$wlan" "$control" "$keyboard" "$menu" "$panel" \
        "$xserver" "${OVERLAY}/etc/init.d/S50jwm"; do
        require_exec "$f"
        sh -n "$f" || die "invalid shell syntax: $f"
    done

    test ! -e "${OVERLAY}/etc/X11/xorg.conf" || die 'static Xorg config must not pin input event numbers'
    require_fragment '/sys/class/input/event*' "$xgen" 'X input devices are not discovered through sysfs'
    require_fragment 'Option "AutoAddDevices" "false"' "$xgen" 'Xorg still depends on udev input hotplug'
    require_fragment 'TOUCH_CALIBRATION' "$xgen" 'persistent touchscreen calibration is missing'
    if grep -Eq '/dev/input/event[0-9]+' "$xgen"; then die 'Xorg generator contains a hard-coded event device'; fi
    require_fragment 'rx1950-xorg-config "$CONFIG"' "$xserver" 'Xorg runtime config is not generated at startup'
    require_fragment '-nolisten tcp' "$xserver" 'Xorg TCP listener is not disabled'
    require_fragment '-dpi "$DPI"' "$xserver" 'global UI DPI is not applied by Xorg'
    require_fragment 'rm -f "${TARGET_DIR}/etc/init.d/S10udev"' "$post" 'resident udev daemon is not suppressed'

    require_fragment '<Dynamic label="Applications">exec:/usr/bin/rx1950-jwm-app-menu</Dynamic>' "$jwm" 'JWM applications menu is not XDG-driven'
    require_fragment '<Include>/root/.config/jwm/panel</Include>' "$jwm" 'JWM panel is not data-driven'
    require_fragment '<Include>/root/.config/jwm/theme</Include>' "$jwm" 'JWM theme is not user-owned'
    require_fragment '/usr/share/applications' "$menu" 'application discovery ignores system desktop files'
    require_fragment '.local/share/applications' "$menu" 'application discovery ignores user desktop files'
    require_fragment 'X-RX1950-Replaces' "$menu" 'desktop wrapper deduplication is missing'
    require_fragment '-sb -rightbar -sl 1000' "${OVERLAY}/usr/bin/mb-applet-xterm-wrapper.sh" 'terminal scrollbar/scrollback profile is missing'
    require_fragment 'jwm -f "$JWMRC"' "${OVERLAY}/etc/init.d/S50jwm" 'JWM is not using user-owned ~/.jwmrc'

    require_fragment 'keyboard*.xml' "$keyboard" 'keyboard layouts are still a closed hard-coded list'
    require_fragment 'REGDOMAIN=' "${OVERLAY}/etc/default/rx1950-wlan" 'WLAN regulatory domain state missing'
    forbid_fragment 'REGDOMAIN=RU' "${OVERLAY}/etc/default/rx1950-wlan" 'image hard-codes Russian regulatory domain'
    require_fragment 'wpa_supplicant -B -D wext' "$wlan" 'ACX100-compatible WEXT association backend missing'
    require_fragment 'udhcpc -i "$ifname" -p "$DHCP_PIDFILE" -n -q' "$wlan" 'WLAN DHCP must be bounded'
    require_fragment 'POWER_MODE=' "${OVERLAY}/etc/init.d/S40wlan" 'WLAN boot path ignores runtime power-mode config'

    require_fragment 'DPI=96' "${OVERLAY}/etc/default/rx1950-ui" 'UI scale state missing'
    require_fragment 'PANEL_HEIGHT=32' "${OVERLAY}/etc/default/rx1950-ui" 'panel size state missing'
    require_fragment 'dpi-set)' "$control" 'GUI backend cannot change global DPI'
    require_fragment 'panel-height-set)' "$control" 'GUI backend cannot change panel geometry'
    require_fragment 'calibrate_touch' "$control" 'touch calibration is not persisted'
    require_fragment 'wifi-country-set)' "$control" 'Wi-Fi country is not configurable'
    require_fragment 'key-set)' "$control" 'hardware button commands are not configurable'

    for obsolete in \
        usr/sbin/rx1950-wifi-ui usr/sbin/rx1950-jwm-status-menu \
        usr/sbin/rx1950-power-menu usr/sbin/rx1950-button-settings \
        usr/bin/rx1950-wifi-launcher; do
        test ! -e "${OVERLAY}/${obsolete}" || die "obsolete terminal/hard-coded UI remains: ${obsolete}"
    done

    require_fragment 'echo 12M > /sys/block/zram0/disksize' "${OVERLAY}/etc/init.d/S20zram" 'zram is not bounded to 12 MiB'
    require_fragment 'echo lzo-rle > /sys/block/zram0/comp_algorithm' "${OVERLAY}/etc/init.d/S20zram" 'zram is not using lzo-rle'
    require_fragment 'read_prop "$d" capacity' "${OVERLAY}/usr/sbin/rx1950-battery" 'battery helper does not consume real power-supply capacity'
    require_fragment 'charge_now' "${OVERLAY}/usr/sbin/rx1950-battery" 'battery helper lacks real charge fallback'

    for f in rx1950-files.desktop rx1950-editor.desktop rx1950-browser.desktop \
        rx1950-terminal.desktop rx1950-settings.desktop; do
        require_file "${OVERLAY}/usr/share/applications/$f"
    done
}

case "${1:-source}" in
    source)
        validate_kernel_config "$KCFG"
        validate_rootfs_config "$RCFG"
        validate_source_runtime
        require_fragment 'XSERVER_XORG_SERVER_DEPENDENCIES += libsha1' "${ROOT_DIR}/buildroot/external/rx1950/external.mk" 'Xorg is not linked to compact libsha1'
        require_fragment '--with-sha1=libsha1' "${ROOT_DIR}/buildroot/external/rx1950/external.mk" 'Xorg SHA1 backend is not compact libsha1'
        ;;
    kernel)
        cfg="${2:-${OUTPUT_DIR}/kernel.config}"; require_file "$cfg"; validate_kernel_config "$cfg"
        require_file "${OUTPUT_DIR}/kernel-modules.tar"
        tar -tf "${OUTPUT_DIR}/kernel-modules.tar" | grep -q '/acx-mac80211\.ko$' || die 'ACX100 module missing from bundle'
        tar -tf "${OUTPUT_DIR}/kernel-modules.tar" | grep -q '/rx1950_acx\.ko$' || die 'rx1950 ACX glue missing from bundle'
        ;;
    rootfs)
        cfg="${2:-${OUTPUT_DIR}/buildroot.config}"; require_file "$cfg"; validate_rootfs_config "$cfg"
        target="${ROOT_DIR}/.build/buildroot-output/target"
        if test -d "$target"; then
            for p in \
                usr/bin/Xorg usr/bin/jwm usr/bin/matchbox-keyboard usr/bin/rx1950-settings \
                usr/bin/pcmanfm usr/bin/leafpad usr/bin/dillo usr/bin/xterm usr/bin/xcalc \
                usr/bin/xinput usr/bin/xinput_calibrator usr/sbin/iw usr/sbin/wpa_supplicant \
                usr/sbin/wpa_passphrase usr/sbin/rx1950-control usr/sbin/rx1950-xorg-config; do
                test -e "$target/$p" || die "built rootfs missing /$p"
            done
            test ! -e "$target/usr/bin/dialog" || die 'dialog remains in built rootfs'
            test ! -e "$target/etc/init.d/S10udev" || die 'resident udev startup remains in built rootfs'
            test ! -e "$target/etc/X11/xorg.conf" || die 'static Xorg config remains in built rootfs'
            if command -v readelf >/dev/null 2>&1; then
                if readelf -d "$target/usr/bin/Xorg" 2>/dev/null | grep -q 'Shared library: \[libcrypto'; then
                    die 'resident Xorg still links libcrypto instead of libsha1'
                fi
            fi
        fi
        ;;
    image)
        validate_kernel_config "${OUTPUT_DIR}/kernel.config"
        validate_rootfs_config "${OUTPUT_DIR}/buildroot.config"
        require_file "${OUTPUT_DIR}/rootfs.ext2"
        ;;
    *) die 'usage: validate-peripherals.sh {source|kernel [config]|rootfs [config]|image}' ;;
esac

printf 'rx1950 peripheral/runtime contract: OK\n'

rx1950-linux boot card

1. Copy this card image to an SD card.
2. Start haret.exe from Windows Mobile.
3. HaRET reads startup.txt, detects RX1950/S3C2442, relocates the image by
   0x1000000, passes machine type 952, and boots zImage. This leaves enough
   room below the compressed image for the current kernel to decompress. The
   script waits 10 seconds before hand-off because Windows Mobile autostart can
   run before all RX1950 hardware has settled.
4. After a reset, haretlog.txt on this FAT partition records HaRET detection
   and the final kernel hand-off.

The internal Windows Mobile installation is not changed.

Packages
--------
rx1950-linux publishes an opkg feed built with the same ARM920T/ARMv4T,
EABI soft-float and musl ABI as the system image. Do not add unrelated
OpenWrt, Entware or Debian repositories: their ARM baseline and/or userspace
ABI is not compatible with this device.

After networking is available:

    opkg update
    opkg list
    opkg install nano

The initial feed includes bash, nano, rsync and tmux plus Buildroot runtime
dependencies not already provided by the base image. Commands already supplied
by BusyBox are deliberately not replaced by opkg packages. The architecture
token is versioned so a future incompatible userspace cannot be installed
accidentally on an older rx1950-linux image.

Engineering-feed integrity currently relies on HTTPS plus the SHA-256 digests
embedded in the opkg index and release checksum manifest. Repository signing is
a separate first-usable-release gate; do not treat the current engineering feed
as cryptographically signed.

WLAN / TI TNETW1100B (ACX100)
-----------------------------
The ACX driver and RX1950 bus glue are shipped as kernel-matched modules.
Proprietary TI firmware is intentionally not redistributed in this image.

The default RX1950 WLAN sequence follows the historical platform driver:
GPH10 provides CLKOUT1, GPA15 is nGCS4, GPC8/GPC9 are asserted high, GPA14
controls reset, GPG8 is EINT16, and GPA11 is the WLAN power line. Mainline
Linux also exposes that same GPA11 line as the visible Blue LED with the
rx1950-acx-mem default trigger, so Blue and WLAN power must be treated as
shared until hardware testing proves otherwise.

With internet access through USB networking, install the separately distributed
firmware from OpenBSD:

    rx1950-wlan-firmware fetch
    rx1950-wlan start
    rx1950-wlan status
    rx1950-wlan scan

The firmware source used by the helper is OpenBSD's acx-firmware-1.4p6 package.
It is copied into the names expected by the Linux ACX driver:
WLANGEN.BIN and RADIOxx.BIN.

To configure WPA/WPA2-PSK:

    { echo 'ctrl_interface=/var/run/wpa_supplicant'; \
      wpa_passphrase 'YOUR_SSID' 'YOUR_PASSWORD'; } > /etc/wpa_supplicant.conf
    rx1950-wlan connect

Then verify:

    ip addr show wlan0
    iw dev wlan0 link
    ping -c 4 1.1.1.1

Blue LED / GPA11
----------------
In the default historical WLAN mode, GPA11 is used as the radio power line and
is also the physical Blue LED. The kernel module drives it through the existing
rx1950-acx-mem LED trigger instead of taking the GPIO away from leds-gpio.
While that mode is active, rx1950-blue refuses manual or netdev-trigger changes
because they could power-cycle the WLAN hardware.

You can inspect the state safely with:

    rx1950-blue status
    rx1950-wlan status

Hardware diagnostic: Blue independence
--------------------------------------
To determine whether the actual RX1950 hardware can operate without GPA11,
stop the normal mode and deliberately test the radio without that line:

    rx1950-wlan restart no-gpa11-power
    rx1950-wlan status
    rx1950-wlan scan

If the interface still appears and scans reliably in no-gpa11-power mode, Blue
can be controlled independently for that test:

    rx1950-blue manual 1
    rx1950-blue manual 0
    rx1950-blue wlan wlan0

Return to the historically documented wiring with:

    rx1950-wlan restart historical

The no-gpa11-power mode is diagnostic until real-device testing establishes
that GPA11 is not required for radio power on this hardware revision.

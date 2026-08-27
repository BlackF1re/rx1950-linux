rx1950-linux boot card

1. Copy this card image to an SD card.
2. Start haret.exe from Windows Mobile.
3. HaRET reads startup.txt, detects RX1950/S3C2442, relocates the image by
   0x1000000, passes machine type 952, and boots zImage. This leaves enough
   room below the compressed image for the current kernel to decompress.
4. After a reset, haretlog.txt on this FAT partition records HaRET detection
   and the final kernel hand-off.

The internal Windows Mobile installation is not changed.

WLAN / TI TNETW1100B (ACX100)
-----------------------------
The ACX driver and RX1950 bus glue are shipped as kernel-matched modules.
Proprietary TI firmware is intentionally not redistributed in this image.

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

Blue LED
--------
Blue is deliberately independent from WLAN by default:

    rx1950-blue manual 1
    rx1950-blue manual 0

It can optionally be assigned to WLAN link/RX/TX activity without changing
radio power:

    rx1950-blue wlan wlan0

Return it to independent manual control with:

    rx1950-blue manual 0

Hardware diagnostic fallback
----------------------------
Historical RX1950 WLAN code also treated GPA11, the physical Blue LED GPIO, as
a WLAN power signal. The normal build does NOT do this because it would make
independent Blue control impossible. If the radio does not appear in normal
mode, collect:

    dmesg | grep -iE 'rx1950-acx|acx|firmware|wlan'
    rx1950-wlan status

Only as a diagnostic comparison, try:

    rx1950-wlan stop
    rx1950-wlan start gpa11-power

That fallback intentionally couples WLAN power and Blue and is not the target
configuration. Do not enable it permanently unless hardware testing proves
GPA11 is electrically required.

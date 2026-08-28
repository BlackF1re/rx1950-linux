# Quick start

This is the shortest path from a stock HP iPAQ rx1950 to the current engineering image. Linux boots entirely from SD through HaRET; the internal Windows Mobile installation is not modified.

## 1. Write the release image

Download `rx1950-linux-<version>.img.xz` and `SHA256SUMS` from [GitHub Releases](https://github.com/BlackF1re/rx1950-linux/releases), verify the checksum, then write the image as a **disk image** to an SD card. Do not copy the `.img.xz` file onto an existing FAT filesystem.

Linux example:

```sh
sha256sum -c SHA256SUMS
xz -dc rx1950-linux-<version>.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

Replace `/dev/sdX` with the whole SD device, not a partition. On Windows, use an imaging tool that can write XZ/raw disk images.

## 2. Boot

1. Power/boot the rx1950 normally into Windows Mobile.
2. Insert the prepared SD card.
3. Open the FAT partition and run `haret.exe`.
4. HaRET reads `startup.txt` and boots the supplied `zImage` with machine type 952.
5. The first Linux boot expands partition 2 and ext4 to the rest of the card. One automatic reboot may occur if the running kernel cannot reread the resized partition table immediately.

Removing the card and resetting returns to the stock Windows Mobile boot path.

## 3. Log in and USB Internet

The engineering image uses a blank root password. On the local console enter only:

```text
login: root
```

USB CDC-NCM keeps the recovery address `192.168.7.2/24` on `usb0` and continuously runs DHCP in parallel. If the PC provides DHCP/NAT — for example Windows Internet Connection Sharing — the PDA automatically adds the host-provided address, default route and DNS while keeping `192.168.7.2`.

Without ICS, put the host side in `192.168.7.0/24` (for example `192.168.7.1`) and connect with:

```sh
ssh root@192.168.7.2
```

With Windows ICS, share the Internet-connected adapter to the `UsbNcm Host Device` adapter. Windows normally assigns the USB side `192.168.137.1/24`; the PDA then obtains a `192.168.137.x` lease automatically. You can SSH to that leased address, or add `192.168.7.1/24` as a secondary host address if you also want the fixed recovery address reachable from the PC.

SSH intentionally permits the blank root password because the device is designed for trusted local links. Do not expose it to an untrusted network.

## 4. HTTPS, time and timezone

CA certificates, OpenSSL and curl are included. A background boot service waits for an Internet route and performs a best-effort NTP synchronization without delaying boot.

The kernel clock remains UTC. To select how local time is displayed, use an IANA timezone name; the setting persists on the writable root filesystem:

```sh
rx1950-timezone Europe/Moscow
rx1950-timezone
```

The complete tzdata database is included, so other names such as `Europe/Helsinki`, `Asia/Tomsk` or `Etc/UTC` can be selected the same way.

## 5. Packages

The image contains `opkg` configured only for the project-owned ARMv4T/EABI soft-float/musl feed. Do not add Debian, OpenWrt or Entware feeds.

```sh
opkg update
opkg list
opkg install nano
```

The initial optional feed contains `bash`, `nano`, `rsync` and `tmux` plus the dependencies not already present in the base image.

## 6. WLAN

The onboard adapter is TI TNETW1100B/ACX100. The driver, RX1950 board glue and verified `WLANGEN.BIN`, `RADIO0d.BIN` and `RADIO11.BIN` firmware payloads are included in the release image.

The physical RX1950 exposed a slave-memory IRQ starvation bug in the historical ACX mac80211 merge path: after the first RX interrupt the old handler masked the device before deferred work could ACK it, causing later firmware commands to time out. The release build carries a local patch that latches and ACKs MEM IRQ causes immediately while leaving expensive descriptor processing deferred.

Basic checks:

```sh
rx1950-wlan status
rx1950-wlan scan
```

For WPA/WPA2-PSK:

```sh
{ echo 'ctrl_interface=/var/run/wpa_supplicant'; \
  wpa_passphrase 'SSID' 'PASSWORD'; } > /etc/wpa_supplicant.conf
rx1950-wlan connect
iw dev wlan0 link
ip addr show wlan0
ping -c 4 1.1.1.1
```

If WLAN fails, collect only the relevant diagnostics:

```sh
rx1950-wlan status
dmesg | grep -iE 'rx1950-acx|acx|firmware|wlan|cfg80211|mac80211'
```

The default WLAN mode follows the historical RX1950 wiring and treats GPA11/Blue as the radio-power line. `no-gpa11-power` exists only for controlled hardware diagnosis; see [hardware.md](hardware.md) before using it.

## 7. Where to look next

- [Hardware support](hardware.md) — what has actually passed on-device acceptance.
- [Hardware inventory](hardware-inventory.md) — component-level map and unresolved hardware.
- [Architecture](architecture.md) — boot/storage/runtime boundaries.
- [Build](build.md) — reproducible build and release pipeline.

The current releases are engineering builds. A green CI run proves build/image contracts, not electrical operation of every peripheral.

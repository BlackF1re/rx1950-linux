# First-boot probe

The engineering image is intentionally observable before it starts a graphical
session. It does not modify Windows Mobile or the internal flash.

## Expected signals

After HaRET reports `booting Linux`, observe the LEDs for 20 seconds, then wait
at least 90 seconds without pressing the reset button. The kernel-only markers
are, in order: a green LED after S3C24xx I/O mapping, a red LED after timer
setup, then a green heartbeat once the LED driver is registered. A successful
root filesystem hand-off additionally produces all of these signals:

1. the green LED turns on when BusyBox userspace starts;
2. the blue LED turns on after the SD root filesystem is available;
3. the Windows-readable FAT partition contains `probe.log` with
   `early-userspace-reached` and `rootfs-ready`;
4. when the sync cable is connected, `probe.log` records either
   `usb-network-ready` or `usb0-unavailable`.

The script deliberately does not start Matchbox. Once framebuffer operation is
confirmed, create `/etc/rx1950/enable-matchbox` and reboot to enable it.

## Reading the result safely

Use the hardware reset control to return to Windows Mobile, remove the card,
and read `probe.log` from the FAT partition on a PC. Never use any Linux
command that targets internal NAND; this probe only mounts `/dev/mmcblk0p1`.

If no log is written but an LED marker is visible, the failure is after that
marker and before BusyBox userspace. If neither LED marker appears, the failure
is before the RX1950 machine callbacks; preserve the exact screen sequence and
report it with the card model and capacity.

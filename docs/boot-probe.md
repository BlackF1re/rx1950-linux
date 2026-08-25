# First-boot probe

The engineering image is intentionally observable before it starts a graphical
session. It does not modify Windows Mobile or the internal flash.

## Expected signals

After HaRET reports `booting Linux`, observe the LEDs for 20 seconds, then wait
at least 90 seconds without pressing the reset button. The final kernel-only
signal is a green heartbeat once the LED driver is registered. (The preceding
GPIO transitions happen too quickly to be a dependable visual test.) A
successful root filesystem hand-off additionally produces all of these signals:

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
and read `earlyharetlog.txt` and `probe.log` from the FAT partition on a PC.
The first is produced by HaRET before it gives control to Linux; the second is
produced only after BusyBox userspace starts. Never use any Linux command that
targets internal NAND; this probe only mounts `/dev/mmcblk0p1`.

If `earlyharetlog.txt` reports a CRC mismatch, Linux was not launched and the
image must not be debugged as a kernel failure. If no `probe.log` is written
but a green heartbeat is visible, the failure is after the kernel LED driver
and before BusyBox userspace. If no heartbeat appears, preserve both logs, the
exact screen sequence, and the card model and capacity.

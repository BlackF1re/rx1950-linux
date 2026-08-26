# First-boot probe

The engineering image is intentionally observable before it starts a graphical
session. It does not modify Windows Mobile or the internal flash.

## Expected signals

The boot card contains a HaRET build that knows the RX1950/S3C2442 machine and
relocates the compressed image by `0x1000000`, away from the Windows Mobile
memory area and above the space required for the current kernel to decompress.
Before testing a new card, run `haret.exe` and confirm that `haretlog.txt`
identifies `RX1950/s3c2442`; a generic Samsung identification means the wrong
executable is still being used.

The green LED is also forced by the zImage entry code, before decompression and
before any Linux board callback. If it never lights while the correct HaRET log
ends with `Go Go Go...`, execution did not reach the image entry instruction.

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
and read `haretlog.txt` and `probe.log` from the FAT partition on a PC. HaRET
writes `haretlog.txt` before it gives control to Linux; `probe.log` is written
only after BusyBox userspace starts. Never use any Linux command that targets
internal NAND; this probe only mounts `/dev/mmcblk0p1`.

If `haretlog.txt` reports a CRC mismatch, Linux was not launched and the image
must not be debugged as a kernel failure. If it ends with `Go Go Go...` but no
`probe.log` is written, use the zImage green-LED signal to distinguish a fault
before decompression from one later in kernel startup. Preserve both logs, the
exact screen sequence, and the card model and capacity.

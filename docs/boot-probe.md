# First-boot probe

The engineering image is intentionally observable before it starts a graphical
session. It does not modify Windows Mobile or the internal flash.

## Expected signals

The boot card contains the RX1950-aware HaRET loader. It identifies the device
as RX1950/S3C2442, uses the 32 MiB SDRAM window at `0x30000000`, passes ARM
machine type `952`, and relocates the compressed kernel by `0x1000000`. The
kernel relocation leaves the Linux 6.2 decompressor enough room to expand the
Image at `RAMADDR + 0x8000` without overwriting unread compressed input.

The FAT partition contains `earlyharetlog.txt`. HaRET treats this file as a
request to open `haretlog.txt` during its own startup and flushes the log before
it takes exclusive control of the CPU. Therefore a crash immediately after the
handoff still leaves the Windows-readable HaRET-side evidence on the card.
After a failed boot, reset the device and confirm that `haretlog.txt` identifies
`RX1950/s3c2442`, reports the configured RAM window and machine type, completes
the kernel CRC check, and reaches the final Linux hand-off. A generic Samsung
identification or a CRC failure is a loader/image failure and must not be
debugged as a Linux board-init failure.

No boot-critical GPIO/LED instrumentation is patched into zImage or
`mach-rx1950.c`. Earlier probes modified registers before the ARM boot ABI and
RX1950 platform initialization were safely established; one probe overwrote
`r1` before Linux saved HaRET's machine ID, and another inserted GPIO calls at
an invalid location in the board source. The kernel now enters the unmodified
upstream Linux 6.2 RX1950 machine callbacks.

The build is rejected unless the final `.config` contains ARM920T, S3C2442,
`MACH_RX1950`, ATAG support, the S3C24XX DMA engine and the S3C MMC host. After
linking, the build additionally verifies that `vmlinux` is an ARM ELF and that
its symbol table contains `__mach_desc_RX1950`. This prevents a successful CI
run from publishing a kernel for a different ARM family or without the RX1950
machine descriptor.

After HaRET hands off to Linux, wait at least 90 seconds without pressing reset.
If the SD root filesystem reaches BusyBox userspace, the early boot service
produces these persistent signals:

1. the green LED is requested through the normal Linux LED class;
2. the blue LED is requested after the root filesystem is available;
3. the Windows-readable FAT partition contains `probe.log` with
   `early-userspace-reached` and `rootfs-ready`;
4. when the sync cable is connected, `probe.log` records either
   `usb-network-ready` or `usb0-unavailable`.

The script deliberately does not start Matchbox. Once framebuffer operation is
confirmed, create `/etc/rx1950/enable-matchbox` and reboot to enable it.

## Reading the result safely

Use the hardware reset control to return to Windows Mobile, remove the card,
and read `haretlog.txt` and `probe.log` from the FAT partition on a PC. HaRET
writes and flushes `haretlog.txt` before it gives control to Linux; `probe.log`
is written only after BusyBox userspace starts. Never use any Linux command
that targets internal NAND; this probe only mounts `/dev/mmcblk0p1`.

If `haretlog.txt` ends at the successful hand-off but `probe.log` is absent, the
failure is inside Linux before userspace. At that point preserve `haretlog.txt`,
the exact screen behaviour, the card model/capacity and the image checksum. The
loader-side ambiguity has already been removed: the published image is accepted
only after its kernel target, RX1950 machine descriptor, decompression window,
partition geometry and embedded root filesystem all pass CI verification.

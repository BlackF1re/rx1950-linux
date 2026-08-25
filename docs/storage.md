# SD-card storage

## Minimal release image

The release image is deliberately only as large as its boot and root contents.
It has no preallocated spare area. The current layout is 65 MiB before
compression:

- the first 1 MiB is the MBR alignment gap;
- partition 1 is a 16 MiB FAT16 boot volume for HaRET, `zImage` and
  `startup.txt`;
- partition 2 is a 48 MiB ext4 Linux root seed.

The exact raw size follows the selected root filesystem size, so it may change
when the base system changes. `rx1950-linux-sd.img.xz` is the release download;
decompress it before writing.

## First Linux boot

The early `S05grow-root` service checks that it is running from the expected
SD-card layout. It then expands only `/dev/mmcblk0p2` to the end of that card
and grows the mounted ext4 filesystem online. No fixed reserve is retained.
If the kernel cannot apply the new partition size while root is mounted, the
service synchronizes and performs one automatic reboot; the next boot grows
the filesystem. A diagnostic marker is written to
`/var/lib/rx1950/root-expanded` after success.

The service refuses to change storage when the root device, partition starts
or FAT boot size do not match the release layout. It does not access the iPAQ
internal flash, Windows Mobile storage or any non-SD device.

## Writing the card

1. Verify `SHA256SUMS` after downloading the release.
2. Decompress `rx1950-linux-sd.img.xz`.
3. Write `rx1950-linux-sd.img` to the whole removable SD card with a raw-image
   writer. Do not copy the file onto a formatted card and do not target the
   iPAQ internal storage.
4. Safely eject the card, insert it into the iPAQ, and launch `haret.exe` from
   the FAT boot partition under Windows Mobile.

Writing the raw image replaces the partition table of the selected removable
card. Select the card device carefully. The first Linux boot makes the rest of
that card available for the root filesystem and `opkg` packages.

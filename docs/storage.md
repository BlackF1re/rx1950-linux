# SD storage

The supported installation is an SD image. Internal NAND/Windows Mobile is not modified.

## Layout

| Region | Purpose |
| --- | --- |
| first 1 MiB | MBR/alignment gap |
| partition 1, 16 MiB FAT16 | `haret.exe`, `startup.txt`, `zImage`, WLAN module bundle and diagnostics |
| partition 2, ext4 seed | Linux root filesystem; currently built as 64 MiB |

The raw image ends at the rootfs seed; it does not preallocate the remainder of the card.

## First boot expansion

`S05grow-root` verifies the expected SD/root device and partition starts, expands only `/dev/mmcblk0p2` to the end of the card, then grows ext4. If Linux cannot reread the new partition size while `/` is mounted, it syncs and performs one automatic reboot before finishing the filesystem grow.

Success is recorded in `/var/lib/rx1950/root-expanded`. Unexpected layouts fail closed; the service does not target internal flash or another block device.

## Writing

Follow [Quick start](QUICKSTART.md): verify `SHA256SUMS` and write `rx1950-linux-<version>.img.xz` as a raw **whole-disk image** to the SD card. Writing the image destroys the previous partition table on the selected card.

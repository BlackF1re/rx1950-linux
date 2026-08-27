# Architecture

## Boot and storage model

The boot path is intentionally non-destructive:

```
Windows Mobile 6.1
        |
        v
HaRET from the SD card FAT partition
        |
        v
Pinned rx1950 compatibility kernel
        |
        v
Linux root filesystem on the SD card ext4 partition
```

HaRET receives only generated, release-owned files: its executable, boot
configuration, kernel, optional initramfs and checksum manifest. It must never
be configured to write the internal flash. The image layout keeps the boot
partition separately mountable from Windows Mobile and Linux.

The raw release image has no reserved tail. It contains a fixed 16 MiB FAT16
boot partition and the smallest ext4 seed filesystem that holds the selected
userspace. At first boot, an early guarded service verifies the expected
layout, extends only the second SD-card partition to the card end, and grows
the mounted ext4 filesystem. If the running kernel cannot reread the changed
partition table, it performs one immediate reboot before the filesystem grow.
It never operates on internal storage or an unexpected partition layout.

## Runtime model

The default system uses a compact BusyBox-oriented userspace and starts only
services that have a device-facing purpose: console, input, storage handling,
network management, time, SSH and the optional graphical session. Diagnostic,
debug and graphical packages are opt-in. Persistent user data and the package
database reside on the SD root/data filesystem.

The base image includes `opkg`, and the engineering image ships a valid local
destination/list configuration so its state is deterministic. It deliberately
contains no remote `src` entry: Buildroot does not produce a compatible binary
package repository, and mixing an unrelated OpenWrt or Entware feed with this
ARMv4T/musl userspace would violate the ABI contract. A project-hosted signed
package feed, package keys, feed URLs and trust policy are a release gate; they
will be versioned alongside the release manifest before packages are
published. Packages are built for ARMv4T, declare their installed size and
dependencies, and must not assume a desktop-class memory budget.

Hardware monitoring uses the in-tree S3C ADC hwmon driver. Battery-voltage ADC
channel 0 is exported with the same board calibration used by the battery
driver, while all eight ADC channels are also exposed as raw values for board
investigation. Standard hwmon consumers use `lm-sensors`; `rx1950-sensors`
adds the raw ADC, thermal-zone and power-supply views without probing unknown
hardware.

## Kernel policy

The upstream legacy machine description is available through Linux 6.2. The
kernel subtree will pin a reviewed compatibility release, its exact source
revision, cross compiler and board configuration. Board changes are stored as
small, numbered patches with rationale and an on-device test reference. Any
forward-port beyond that baseline is an explicit engineering effort, not a
version-only upgrade.

Boot-critical platform devices are intentionally kept on the upstream RX1950
registration path. Optional engineering devices must not be inserted into the
`platform_add_devices()` array: that helper unregisters every earlier device
if any later registration fails, so an experimental peripheral must never be
able to remove the SD controller that provides the root filesystem. The S3C
hwmon device is therefore registered separately after the core board array.

The 0.1.14 engineering image violated that rule while also changing the legacy
S3CMCI CD/WP probe control flow. On hardware it reached the kernel and then
panicked with `VFS: Unable to mount root fs on unknown-block(179,2)`. The
published image layout and ext4 superblock were verified structurally against
the booting 0.1.13 image, so the regression is treated as a kernel-side
boot-path failure. Both risky changes are reverted; SD/MMC remains on the
previously boot-tested PIO path.

S3C2442 DMA support remains compiled into the compatibility kernel, but the DMA
platform device is not registered by the RX1950 board until a non-regressive
activation design is validated on hardware. Consequently UDA1380 PCM remains
blocked at the DMA acquisition stage for now; preserving bootable storage takes
priority over enabling audio through an unverified early platform change.

## Artifact contract

A release contains the compressed SD image, SHA-256 checksum, software bill of
materials, build provenance, HaRET boot files, package-feed key and hardware
acceptance report. Continuous integration builds each component independently,
then assembles and inspects the final image. Publishing is gated on reproducible
inputs and the complete hardware report described in [goals.md](goals.md).

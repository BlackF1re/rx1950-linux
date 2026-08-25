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
Linux root filesystem on the SD card ext2 partition
```

HaRET receives only generated, release-owned files: its executable, boot
configuration, kernel, optional initramfs and checksum manifest. It must never
be configured to write the internal flash. The image layout keeps the boot
partition separately mountable from Windows Mobile and Linux.

## Runtime model

The default system uses a compact BusyBox-oriented userspace and starts only
services that have a device-facing purpose: console, input, storage handling,
network management, time, SSH and the optional graphical session. Diagnostic,
debug and graphical packages are opt-in. Persistent user data and the package
database reside on the SD root/data filesystem.

The base image includes `opkg` so optional software can be installed without
inflating the default root filesystem. A project-hosted signed package feed,
package keys, feed URLs and trust policy are a release gate; they will be
versioned alongside the release manifest before packages are published.
Packages are built for ARMv4T, declare their installed size and dependencies,
and must not assume a desktop-class memory budget.

## Kernel policy

The upstream legacy machine description is available through Linux 6.2. The
kernel subtree will pin a reviewed compatibility release, its exact source
revision, cross compiler and board configuration. Board changes are stored as
small, numbered patches with rationale and an on-device test reference. Any
forward-port beyond that baseline is an explicit engineering effort, not a
version-only upgrade.

## Artifact contract

A release contains the compressed SD image, SHA-256 checksum, software bill of
materials, build provenance, HaRET boot files, package-feed key and hardware
acceptance report. Continuous integration builds each component independently,
then assembles and inspects the final image. Publishing is gated on reproducible
inputs and the complete hardware report described in [goals.md](goals.md).

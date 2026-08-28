# rx1950-linux

`rx1950-linux` is a compact, reproducible GNU/Linux system for the HP iPAQ
rx1950. It boots from an SD card through HaRET and does not modify the
device's internal Windows Mobile installation.

The project is designed for a useful everyday handheld rather than a demo:
the base image is deliberately small, while a native project package feed makes
it possible to add software without rebuilding the system. Every hardware
feature has a documented support state and an on-device acceptance test.

## Design constraints

- **Non-destructive boot:** Windows Mobile and the internal flash remain
  untouched. Removing the card restores the original boot path.
- **Actual target:** Samsung S3C2442 at 300 MHz, ARM920T / ARMv4T, 32 MiB RAM,
  64 MiB ROM, QVGA 240x320 display, and SD/SDIO/MMC slot.
- **Small but extensible:** BusyBox-based base system, read-write ext4 data
  partition, SSH administration, and a project-owned `opkg` package feed built
  with the same ARMv4T/EABI soft-float/musl ABI as the image. Unrelated
  OpenWrt, Entware or Debian feeds are intentionally unsupported.
- **Maintained where feasible:** the hardware machine support exists in
  upstream Linux through 6.2. The kernel is consequently a separately pinned,
  security-reviewed compatibility baseline; claiming that a current upstream
  kernel boots this legacy ARMv4T board would be inaccurate.
- **Reproducible artifacts:** a release is an SD image plus checksums,
  provenance, boot files, package-feed metadata, and an acceptance report.

## Target for the first usable release

1. A FAT boot partition containing HaRET, kernel and a generated boot script.
2. A Linux ext4 root partition which remains independent from the Windows
   Mobile-readable boot volume and grows to the end of the card at first boot.
3. Console, QVGA framebuffer, touchscreen, physical buttons, SD storage,
   backlight, battery status, audio, USB gadget, RTC, infrared and WLAN where
   their device-specific drivers pass on-device tests.
4. A compact launcher-oriented graphical session, terminal, Wi-Fi setup,
   suspend controls and SSH. Features remain disabled by default until they
   have passed their corresponding test.
5. An architecture-compatible `opkg` feed with tested install/remove/update
   semantics and a release trust policy. The feed is already generated and
   validated in CI; cryptographic package-index signing remains a release gate
   until its memory/storage cost and recovery path are validated on hardware.

The current engineering image remains a hardware-validation build rather than
a claim that every peripheral is supported. It keeps the proven SD/root boot
path isolated from experimental peripherals, provides USB CDC-NCM/SSH recovery,
and carries kernel-matched optional WLAN modules separately from the boot
kernel. Proprietary TI ACX100 firmware is not redistributed. See the
[hardware support matrix](docs/hardware.md) for the exact status of each
subsystem before testing a new image.

The boot and storage contract is in [the architecture guide](docs/architecture.md),
and [the delivery plan](docs/goals.md) defines the completion criteria.

## Package feed

The package feed is generated from the exact Buildroot 2025.02.2 toolchain and
finalized target used by the system image. Packages use the versioned
`rx1950_armv4t_musl_v1` architecture token and are rejected by CI if they would
overwrite files belonging to the sealed base image.

The initial feed is intentionally small and currently provides `bash`, `nano`,
`rsync` and `tmux` together with their runtime dependencies not already present
in the base image. Package metadata, checksums, conffiles and required
maintainer hooks are generated alongside the `.ipk` files.

After networking is available on a compatible engineering release:

```sh
opkg update
opkg list
opkg install nano
```

## Repository layout

- `.github/workflows/` — reproducible build, validation and release jobs.
- `board/` — board-specific kernel configuration and boot assets.
- `buildroot/` — pinned build system and external tree for the minimal base.
- `kernel/` — pinned kernel source policy, configuration, optional modules and
  board patches.
- `scripts/` — build, image, package-feed, validation and release tooling.
- `docs/` — installation, architecture, hardware and maintenance reference.

## Build and release status

The release workflow validates the source contract, builds the root filesystem
and kernel independently, builds and validates the native package feed, verifies
stage hand-off digests, then assembles and inspects the SD-card image. The
resulting Actions artifacts contain the sealed image, kernel/rootfs outputs and
package feed. Publishing from the release workflow creates an engineering
release from the same validated outputs rather than rebuilding different
payloads afterward.

A green CI build proves the source, ABI, packaging and image contracts that can
be checked without the handheld. It is not evidence that an experimental
peripheral works electrically on a physical rx1950. Hardware support is only
promoted after its on-device acceptance result is recorded in
[hardware.md](docs/hardware.md).

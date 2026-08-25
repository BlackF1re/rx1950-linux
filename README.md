# rx1950-linux

`rx1950-linux` is a compact, reproducible GNU/Linux system for the HP iPAQ
rx1950. It boots from an SD card through HaRET and does not modify the
device's internal Windows Mobile installation.

The project is designed for a useful everyday handheld rather than a demo:
the base image is deliberately small, while an optional package feed makes it
possible to add software without rebuilding the system. Every hardware feature
has a documented support state and an on-device acceptance test.

## Design constraints

- **Non-destructive boot:** Windows Mobile and the internal flash remain
  untouched. Removing the card restores the original boot path.
- **Actual target:** Samsung S3C2442 at 300 MHz, ARM920T / ARMv4T, 32 MiB RAM,
  64 MiB ROM, QVGA 240x320 display, and SD/SDIO/MMC slot.
- **Small but extensible:** BusyBox-based base system, read-write ext4 data
  partition, SSH administration, and a repository-backed `opkg` package
  manager. The package manager and its trust policy are part of the release,
  not an afterthought.
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
5. A signed feed of architecture-compatible `opkg` packages, with the base
   image kept intentionally modest.

The current engineering image is a hardware boot probe, not a usable release.
It writes explicit userspace and USB milestones to the Windows-readable FAT
partition and holds the graphical session back until the framebuffer has been
verified. See [the first-boot probe guide](docs/boot-probe.md) before writing an
image to a card.

The full, testable inventory is in [the hardware support matrix](docs/hardware.md).
The boot and storage contract is in [the architecture guide](docs/architecture.md),
and [the delivery plan](docs/goals.md) defines the completion criteria.

## Repository layout

- `.github/workflows/` — reproducible build, validation and release jobs.
- `board/` — board-specific kernel configuration and boot assets.
- `buildroot/` — pinned build system and external tree for the minimal base.
- `kernel/` — pinned kernel source policy, configuration and board patches.
- `scripts/` — build, image, validation and release tooling.
- `docs/` — installation, architecture, hardware and maintenance reference.

## Build and release status

Every push to `main` builds the root filesystem and kernel independently,
verifies their hand-off digests, assembles a content-sized SD-card image and publishes
the sealed payload as an Actions artifact. A maintainer can then run the same
workflow manually with publishing enabled to create a GitHub release containing
the image, checksum, provenance, kernel and HaRET startup script.

The automated artifact is a reproducible engineering build, not an assertion
that every peripheral has passed on a physical handheld. The first public
release is gated by the device acceptance record in
[goals.md](docs/goals.md).

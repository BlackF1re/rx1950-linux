# rx1950-linux

[![Latest Release](https://img.shields.io/github/v/release/BlackF1re/rx1950-linux?include_prereleases&sort=semver&label=release)](https://github.com/BlackF1re/rx1950-linux/releases) [![Latest Release Date](https://img.shields.io/github/release-date-pre/BlackF1re/rx1950-linux?display_date=published_at&label=latest%20release)](https://github.com/BlackF1re/rx1950-linux/releases) [![Release Pipeline](https://img.shields.io/github/actions/workflow/status/BlackF1re/rx1950-linux/build-release.yml?branch=main&event=push&label=release%20pipeline)](https://github.com/BlackF1re/rx1950-linux/actions/workflows/build-release.yml) [![License](https://img.shields.io/github/license/BlackF1re/rx1950-linux?label=license)](LICENSE)

`rx1950-linux` is a compact GNU/Linux distribution for the HP iPAQ rx1950. It boots from SD through HaRET, keeps the internal Windows Mobile installation untouched, and targets the real S3C2442/ARM920T platform: 300 MHz ARMv4T, 32 MiB RAM and a 240x320 display.

The base image is intentionally small. Additional software comes from a project-owned `opkg` feed built for the same ARMv4T/EABI soft-float/musl ABI.

## What works

- SD boot/root filesystem with automatic first-boot expansion.
- 240x320 framebuffer, PWM backlight, resistive touchscreen and physical keys.
- Battery/ADC monitoring and red/green/blue LED class devices.
- USB CDC-NCM recovery network with SSH at `192.168.7.2`.
- Native `opkg` feed; initial optional packages include `bash`, `nano`, `rsync` and `tmux`.
- TI TNETW1100B/ACX100 WLAN driver and RX1950 board glue are included as isolated modules; physical radio acceptance is still in progress and proprietary firmware is not redistributed.

Audio PCM, IrDA, RTC/suspend acceptance, NAND inspection and the remaining board-level hardware are tracked explicitly rather than advertised early. See [hardware.md](docs/hardware.md) and [hardware-inventory.md](docs/hardware-inventory.md).

## Start here

Download `rx1950-linux-<version>.img.xz` from [GitHub Releases](https://github.com/BlackF1re/rx1950-linux/releases), write it as a raw disk image to an SD card, boot Windows Mobile, insert the card and run `haret.exe` from its FAT partition.

The default engineering login is `root` / `rx1950`. Change it before using an untrusted network.

Full first-boot, USB, package and WLAN steps are in [Quick start](docs/QUICKSTART.md).

## Design

- **Non-destructive:** the supported path never installs to internal NAND; removing the SD card restores the stock boot path.
- **Fail-isolated:** optional hardware such as WLAN is kept out of the boot-critical RX1950 platform-device path, so an experimental peripheral cannot unregister the SD controller that owns `/`.
- **Board-specific:** Linux 6.2 is pinned because it is the last upstream kernel carrying the legacy RX1950 machine support; forward ports are explicit engineering work.
- **Extensible:** packages come only from the versioned `rx1950_armv4t_musl_v1` feed. Debian/OpenWrt/Entware feeds are ABI-incompatible.
- **Reproducible:** release payload generation fixes the build epoch, kernel identity, ext4 UUID/hash seed, FAT metadata, MBR signature, tar metadata and XZ threading. Commit identity stays in provenance rather than altering runtime bits.

## Build and release

Pinned inputs are Buildroot 2025.02.2, Linux 6.2, the RX1950 HaRET binary and a pinned ACX mac80211 revision. A local complete build is:

```sh
bash scripts/build.sh all
```

GitHub Actions builds rootfs and kernel independently, validates the native package feed, verifies stage digests, assembles the SD image and publishes only that verified payload. See [build.md](docs/build.md).

## Repository layout

- `board/` — HaRET boot assets and board-facing notes.
- `buildroot/` — ARMv4T userspace configuration and rootfs overlay.
- `kernel/` — Linux configuration, patches and optional RX1950 modules.
- `scripts/` — build, package-feed and validation tooling.
- `docs/` — operator and hardware-engineering documentation.
- `.github/workflows/` — CI and release pipeline.

## Documentation

Start with [docs/README.md](docs/README.md). Hardware claims require physical-device evidence; CI success alone is not treated as proof that a peripheral works electrically.

License: [GNU GPL v2](LICENSE). Imported/upstream components retain their own licence notices.

# Architecture

## Boot and storage

```text
Windows Mobile 6.1
        ↓
HaRET on SD/FAT16
        ↓
Linux 6.2 RX1950 compatibility kernel
        ↓
SD partition 2 / ext4 root
```

The supported path is deliberately non-destructive. HaRET boots only release-owned files from SD; documented Linux tools do not install to internal NAND. Removing the card restores the stock Windows Mobile path.

The image contains a 16 MiB FAT boot partition and an ext4 root seed. `S05grow-root` verifies the expected layout, expands only `/dev/mmcblk0p2` to the card end and grows ext4. See [storage.md](storage.md).

## Boot-safety boundary

The RX1950 SD controller owns the root filesystem, so experimental devices must never be able to unregister or destabilize it.

Linux `platform_add_devices()` rolls back devices already registered in the same array if a later registration fails. The 0.1.14 engineering image violated this safety boundary while experimenting with peripheral/DMA registration and failed on hardware with `unknown-block(179,2)`.

Policy since 0.1.15:

- keep the upstream S3CMCI/root path unchanged;
- keep optional engineering devices outside the boot-critical board array;
- load WLAN only as kernel-matched modules after root is available;
- leave S3C2442 DMA compiled but do not activate the unsafe early RX1950 DMA path until audio can be restored without risking storage.

USB CDC-NCM/SSH remains the recovery channel after userspace starts.

## Userspace and packages

The base is Buildroot/BusyBox with Dropbear, hardware diagnostics, WLAN tools and a small Matchbox/TinyX session. The system ABI is ARM920T/ARMv4T, EABI, soft-float, musl.

`opkg` uses only the project feed (`rx1950_armv4t_musl_v1`). Packages are built with the same Buildroot toolchain as the image. CI rejects packages that overwrite sealed base files, collide with another package, have unresolved dependencies or contain the wrong ARM ABI. `/etc` package files are emitted as conffiles.

Unrelated Debian, OpenWrt and Entware feeds are not compatible.

Engineering-feed transport currently relies on HTTPS plus SHA-256 package/index manifests. Cryptographic repository signing remains a usability-release gate because its GPGME footprint must first be measured on the 32 MiB target.

## Kernel and hardware policy

Linux 6.2 is pinned because it is the last upstream release carrying the legacy RX1950 machine description. Newer kernels require an explicit forward-port and equivalent physical testing.

The onboard TI TNETW1100B/ACX100 uses a pinned mac80211 memory-transport driver plus a small RX1950 glue module. Proprietary firmware is external. The default glue follows the historical RX1950 wiring, including the GPA11/Blue shared power line; the alternative no-GPA11 mode is diagnostic only until hardware proves independence.

Hardware support claims are kept separate from code presence: [hardware.md](hardware.md) is the release acceptance matrix and [hardware-inventory.md](hardware-inventory.md) is the component-level engineering map.

## Reproducibility and provenance

Release payloads normalize build time/locale, kernel build identity, ext4 UUID/hash seed, FAT metadata, MBR signature, module archive metadata and XZ threading. Buildroot reproducible mode is enabled. Identical source tree/configuration/version is expected to yield identical payload hashes.

The Git commit is recorded separately in `provenance.txt`; it must not make otherwise identical PR/main binaries differ. See [build.md](build.md).

## Release boundary

A release is assembled only from already validated rootfs/kernel artifacts and the separately validated package feed. Publication does not rebuild them. CI can prove source, ABI, filesystem and artifact contracts; only an on-device test can promote a peripheral to supported.

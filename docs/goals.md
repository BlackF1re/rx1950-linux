# Release gates

A feature is supported only when it is present in the image **and** has a repeatable result on a physical rx1950. Compilation/CI alone is not hardware evidence.

## Product contract

- Boot from SD through HaRET without writing internal NAND/Windows Mobile.
- FAT boot partition readable by Windows Mobile; ext4 root expands to the SD-card end on first boot.
- Keep the 32 MiB system responsive by making the base image small and installing optional software through the native `opkg` feed.
- Experimental peripherals must fail without breaking SD root, console or USB recovery.

## Gates

| Gate | Required evidence |
| --- | --- |
| Reproducibility | Identical source tree/configuration/version produces byte-identical kernel, rootfs, module bundle, image and package payloads; source commit is recorded separately in provenance. |
| Boot safety | HaRET boots the shipped kernel; removing SD returns to Windows Mobile; documented paths issue no internal-flash writes. |
| Storage | FAT is readable; root expansion touches only expected `/dev/mmcblk0p2`; read/write/remount and recovery tests pass. |
| Base system | Console, persistent root, USB/SSH recovery and `opkg` operate after cold boot. |
| Hardware | Applicable rows in [hardware.md](hardware.md) have recorded on-device results. |
| Power | Battery/charger reporting, display blanking, shutdown and suspend/resume have safe recovery behaviour. |
| Networking | WLAN scan, association, DHCP/DNS, sustained transfer and reconnect pass on supported AP settings. |
| Package management | Feed update/install/remove/reinstall, dependency handling, conffiles, low-space and interrupted-operation behaviour pass on hardware. |
| Usability | Touch calibration, physical navigation, QVGA UI and on-screen keyboard work within measured RAM/storage limits. |
| Trust | A generally usable release must authenticate package/release metadata; the engineering feed currently uses HTTPS + SHA-256 but is not yet cryptographically signed. |

## Current priorities

1. Preserve the proven SD/root/USB recovery path.
2. Complete physical WLAN acceptance.
3. Restore audio through a safe, isolated S3C2442 DMA design.
4. Validate RTC, suspend/wakeup, IrDA/UART and read-only NAND inventory.
5. Resolve ADC2-ADC7 and the board-level components tracked in [hardware-inventory.md](hardware-inventory.md).
6. Finalize the PDA-oriented GUI and package/release trust path.

## Boundaries

The supported path does not install Linux to internal NAND. The RX1950 has no integrated Bluetooth, GPS, cellular modem, camera or 3D accelerator. Linux newer than 6.2 requires an explicit RX1950 forward-port because the legacy machine support was removed upstream.

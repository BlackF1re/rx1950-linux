# Delivery plan and release gates

This document defines “complete” for rx1950-linux. A feature is not called
supported because it compiles: it must be present in the image, exerciseable
on the physical device, and have a repeatable test result recorded for the
release.

## Product contract

The supported boot route is an SD card launched from Windows Mobile using
HaRET. The installer must not repartition, erase, flash or otherwise change
the device's internal ROM or NAND. A user must be able to recover the original
Windows Mobile boot simply by removing the card and resetting the device.

The shipped image must fit a 1 GiB or larger SD card, expose a FAT boot volume
that Windows Mobile can read, use an ext2 Linux data volume, and retain enough
free space and RAM headroom for interactive use on a 32 MiB machine. The
default image is minimal; applications are added through the project package
feed using `opkg`.

## Release gates

| Gate | Evidence required before release |
| --- | --- |
| Reproducible build | Clean, pinned-source build on GitHub Actions; manifests, SHA-256 sums and tool versions are saved with the artifact. |
| Boot safety | HaRET starts the exact kernel in the image; removing the SD card demonstrably returns to Windows Mobile. No internal flash write is issued by any documented path. |
| Storage | FAT boot files are readable under Windows Mobile; SD card detection, read/write, remount and unclean-removal recovery pass. |
| Base system | `init`, console login, UTC RTC, writable persistent data, SSH and package database work after a cold boot. |
| Hardware | Each applicable item in the hardware matrix has an on-device result. Unverified items stay marked experimental or unavailable. |
| Power | Battery reporting, controlled shutdown, display blanking and suspend/resume are tested independently. A failure must leave a documented safe recovery path. |
| Networking | WLAN association, DHCP, DNS, TCP transfer and reconnection after suspend pass with the supported access-point security. |
| Updates | The feed key, package signature verification, upgrade, rollback/recovery instructions and available-space checks are tested on a freshly written card. |
| Usability | Touch calibration persists; the graphical session, keyboard path, physical navigation and readable QVGA layout are exercised without external serial equipment. |

## Work sequence

1. Pin and build the compatibility kernel, cross toolchain and HaRET assets;
   generate a bootable two-partition SD image.
2. Bring up console, LCD/backlight, touchscreen, physical keys, SD/MMC and
   persistent storage. This is the minimum safe test image.
3. Enable RTC, battery/charging reporting, LEDs, audio, USB gadget/client,
   infrared and WLAN, documenting chipset-specific firmware or legal
   redistribution constraints.
4. Add the small graphical session and input methods, then measure cold-boot
   time, idle RAM, interactive RAM and image size on real hardware.
5. Produce the signed `opkg` repository and define upgrade compatibility,
   key rotation and failure recovery.
6. Automate image inspection and test reports in Actions; publish only the
   artifact set that meets every release gate above.

## Non-goals and honest boundaries

- No internal-flash Linux installer is planned for the supported path.
- The device has no integrated Bluetooth, camera, cellular modem, GPS, video
  output or hardware 3D accelerator. SDIO accessories are supported only when
  their driver, firmware and power requirements are separately validated.
- A modern desktop environment, web browser or general Python distribution is
  outside the default image budget. Small command-line and graphical packages
  remain available when they are compatible with ARMv4T and the package feed.
- Mainline kernels newer than 6.2 do not include `CONFIG_MACH_RX1950`; a newer
  kernel requires an explicitly maintained forward-port and equivalent device
  testing before it can replace the compatibility baseline.

# Hardware support matrix

Status is deliberately conservative. **Planned** means the board support or
published specifications identify the hardware, but this project has not yet
recorded a passing test on an rx1950. **Experimental** means it has booted or
been detected but lacks the release test suite. Only **Supported** may appear
in a release claim.

## Platform and interactive hardware

| Subsystem | Known implementation | Status | Required release test |
| --- | --- | --- | --- |
| CPU and memory | Samsung S3C2442, 300 MHz ARM920T/ARMv4T; 32 MiB SDRAM | Planned | Kernel boots, reports memory, runs a sustained userspace stress test. |
| Internal flash | 64 MiB ROM / NAND, reserved for Windows Mobile | Protected | Verify no boot, install, update or recovery command writes it. |
| SD/MMC/SDIO | S3C24xx MCI; 1-bit/4-bit SD, MMC and SDIO slot | Planned | Detect card, boot rootfs, read/write/remount, card-detect and write-protect. |
| LCD | 3.5-inch transflective 65k-colour QVGA TFT; S3C24xx framebuffer | Planned | Native 240x320 console and graphical session, orientation, long-running redraw. |
| Backlight | PWM-controlled panel backlight | Planned | Brightness range, blank/unblank and recovery after suspend. |
| Touchscreen | SoC ADC/resistive single-touch controller | Planned | Calibration, edge accuracy, drag, wake input and persistent calibration. |
| D-pad and action key | GPIO keys: up, down, left, right, enter | Planned | Every key produces its expected evdev code in console and graphical session. |
| Application keys | Power, record, calendar, contacts, mail and WLAN GPIO keys | Planned | Event mapping, long press where applicable, and non-destructive power action. |
| LEDs | Red, green and WLAN indicators on GPIO | Planned | Trigger, manual on/off and safe power-state transition. |
| RTC | S3C24xx RTC | Planned | Set/read UTC, retain time over reset and restore system clock at boot. |

## Connectivity and expansion

| Subsystem | Known implementation | Status | Required release test |
| --- | --- | --- | --- |
| WLAN | Integrated IEEE 802.11b TI TNETW1100B on a memory-mapped bus; its legacy `acx-mem` driver and board glue are not in Linux 6.2 | Driver port required | Port the driver and GPIO power/reset/IRQ wiring, then scan, associate, DHCP, DNS, transfer and reconnect. |
| Bluetooth | No integrated controller | Not applicable | SDIO Bluetooth cards are separate optional peripherals. |
| Infrared | IrDA SIR/CIR port | Planned | `irda` stack discovery and bidirectional transfer with a known peer. |
| USB device | S3C2410 UDC via 22-pin connector; RNDIS Ethernet gadget is enabled in the engineering image | Experimental | Windows enumerates the USB network adapter; `192.168.7.2` answers SSH after a cold boot; disconnect and reconnect work cleanly. |
| USB host | Connector/dock capability is not assumed | Research required | Identify electrical support before exposing a host-mode configuration. |
| Serial | Dock connector RS-232 path | Research required | Identify cable and signal levels; console transfer test after confirmation. |
| SDIO accessories | Slot supports SDIO electrically | Experimental | Each card model gets an individual driver, firmware, power and stability test. |

## Audio and power

| Subsystem | Known implementation | Status | Required release test |
| --- | --- | --- | --- |
| Audio codec | UDA1380 on I2C/I2S | Planned | Stereo playback to 3.5 mm jack, speaker route, levels and underrun-free playback. |
| Microphone | Integrated mono microphone | Planned | Capture, playback and gain/noise verification. |
| Speaker and headphone detect | GPIO-routed speaker power and headphone sense | Planned | Route switching and no audible pop across power/suspend transitions. |
| Battery | Removable 1100 mAh Li-ion pack | Planned | Capacity, voltage, charging state and low-battery behaviour against physical readings. |
| Suspend/resume | SoC power management plus board state restoration | Experimental | Repeated suspend/resume with display, touch, WLAN and storage; forced-reset recovery documented. |
| Watchdog | S3C24xx watchdog | Planned | Deliberate watchdog reset in a disposable test image only. |

## Software and boot surface

| Subsystem | Status | Required release test |
| --- | --- | --- |
| HaRET launch | Planned | Launch from Windows Mobile with generated configuration; verify kernel command line and RAM addresses. |
| FAT boot partition | Planned | Windows Mobile can read all shipped boot files and checksum manifest. |
| Linux root partition | Planned | ext2 mounts read-write and preserves the boot partition; a larger-card layout and growth path are tested separately. |
| Console and SSH | Experimental | Local framebuffer terminal works; remote SSH works after cold boot over the USB RNDIS link and WLAN once that driver is validated. |
| Package management | Planned | `opkg update`, signature check, install, remove and recovery from interrupted transaction. |
| Graphical session | Experimental | The image includes the Matchbox session (TinyX, launcher, panel and on-screen keyboard); verify QVGA startup, stylus, physical navigation, idle RAM and clean exit on the device. |

## Sources and verification record

The published HP specification identifies the S3C2442, 32 MiB RAM, 64 MiB ROM,
QVGA display, SD/SDIO/MMC slot, 802.11b WLAN, removable 1100 mAh battery,
infrared, USB/serial dock connector and audio interfaces. The historical
upstream board file enumerates the platform devices, GPIO key map, UDA1380
codec, MCI wiring, framebuffer/backlight, RTC, USB device controller, NAND,
battery and LEDs. The kernel configuration selects the corresponding in-tree
drivers as built-ins, so the image does not depend on an unshipped module tree.
The TI WLAN driver remains an explicit exception: it requires a maintained
port before it can be claimed as available. The Linux Kernel Driver Database
records the in-tree machine configuration through Linux 6.2.

Primary references:

- HP, [iPAQ rx1950 specifications](https://support.hp.com/cn-zh/document/c01203014)
- Linux, [historical rx1950 board support](https://code.googlesource.com/linux/torvalds/linux/+/18ded910b589839e38a51623a179837ab4cc3789/arch/arm/mach-s3c24xx/mach-rx1950.c)
- Linux Kernel Driver Database, [`CONFIG_MACH_RX1950`](https://cateee.net/lkddb/web-lkddb/MACH_RX1950.html)

Each release adds dated results, kernel revision, card model and test notes to
this section. A missing result is a failed release gate, not implicit support.

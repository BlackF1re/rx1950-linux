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
| SD/MMC/SDIO | S3C24xx MCI; 1-bit/4-bit SD, MMC and SDIO slot | Experimental | Boot-tested on 0.1.13; re-verify cold boot, read/write/remount, card-detect and write-protect after the 0.1.14 regression rollback. |
| LCD | 3.5-inch transflective 65k-colour QVGA TFT; S3C24xx framebuffer | Planned | Native 240x320 console and graphical session, orientation, long-running redraw. |
| Backlight | PWM-controlled panel backlight | Experimental | Brightness control is verified on hardware; still verify blank/unblank and recovery after suspend. |
| Touchscreen | SoC ADC/resistive single-touch controller | Experimental | Basic touch is verified; still verify calibration, edge accuracy, drag, wake input and persistent calibration. |
| D-pad and action key | GPIO keys: up, down, left, right, enter | Experimental | Basic button input is verified; still verify every expected evdev code and graphical-session behaviour. |
| Application keys | Power, record, calendar, contacts, mail and WLAN GPIO keys | Experimental | Basic button input is verified; still verify complete mapping, long press where applicable, and non-destructive power action. |
| LEDs | Red, green and WLAN indicators on GPIO | Experimental | Manual on/off is verified on hardware; still verify triggers and safe power-state transitions. |
| RTC | S3C24xx RTC | Planned | Set/read UTC, retain time over reset and restore system clock at boot. |
| Hardware monitoring | S3C2442 ADC via separately registered `s3c-hwmon`; scaled battery voltage plus raw ADC channels 0-7 | Experimental | Run `sensors` and `rx1950-sensors`, verify stable readings alongside touchscreen/battery use, and compare battery voltage against a physical reading. |

## Connectivity and expansion

| Subsystem | Known implementation | Status | Required release test |
| --- | --- | --- | --- |
| WLAN | Integrated IEEE 802.11b TI TNETW1100B/ACX100 on the external memory bus; pinned ACX mac80211 slave-memory driver plus isolated RX1950 GPIO/MMIO glue are built as kernel-matched modules; proprietary firmware remains external | Planned | Import firmware, load modules without disturbing SD/root, verify `iw dev`, scan, WPA/WPA2 association, DHCP, DNS, sustained TCP transfer and reconnect; compare historical GPA11 power mode with `no-gpa11-power` and verify Blue LED behaviour. |
| Bluetooth | No integrated controller | Not applicable | SDIO Bluetooth cards are separate optional peripherals. |
| Infrared | IrDA SIR/CIR port | Planned | `irda` stack discovery and bidirectional transfer with a known peer. |
| USB device | S3C2410 UDC via 22-pin connector; CDC-NCM Ethernet gadget is enabled in the engineering image for native Windows 11/Linux host support | Experimental | Windows 11 enumerates the inbox `UsbNcm.sys` network adapter without an external INF; `192.168.7.2` answers SSH after a cold boot; disconnect and reconnect work cleanly. |
| USB host | Connector/dock capability is not assumed | Research required | Identify electrical support before exposing a host-mode configuration. |
| Serial | Dock connector RS-232 path | Research required | Identify cable and signal levels; console transfer test after confirmation. |
| SDIO accessories | Slot supports SDIO electrically | Experimental | Each card model gets an individual driver, firmware, power and stability test. |

## Audio and power

| Subsystem | Known implementation | Status | Required release test |
| --- | --- | --- | --- |
| Audio codec | UDA1380 on I2C/I2S; PCM currently blocked by missing safe S3C2442 DMA activation | Planned | Design DMA activation that cannot affect the SD boot path, then verify stereo playback to 3.5 mm jack, speaker route, levels and underrun-free playback. |
| Microphone | Integrated mono microphone | Planned | Capture, playback and gain/noise verification. |
| Speaker and headphone detect | GPIO-routed speaker power and headphone sense | Planned | Route switching and no audible pop across power/suspend transitions. |
| Battery | Removable 1100 mAh Li-ion pack; S3C ADC reporting is active | Experimental | Voltage and charging state are observed; still verify cable transitions, capacity and low-battery behaviour against physical readings. |
| Suspend/resume | SoC power management plus board state restoration | Experimental | Repeated suspend/resume with display, touch, WLAN and storage; forced-reset recovery documented. |
| Watchdog | S3C24xx watchdog | Planned | Deliberate watchdog reset in a disposable test image only. |

## Software and boot surface

| Subsystem | Status | Required release test |
| --- | --- | --- |
| HaRET launch | Experimental | The machine type is passed by HaRET and the loader log survives handoff; keep verifying on physical hardware. |
| FAT boot partition | Experimental | Windows Mobile can read shipped boot files and persistent HaRET diagnostics. |
| Linux root partition | Experimental | 0.1.13 boots and grows ext4 successfully; re-verify the post-0.1.14 rollback image on physical media. |
| Console and SSH | Experimental | Local framebuffer console and SSH over USB CDC-NCM are verified on the booting engineering image; still verify reconnect and long-running stability. |
| Package management | Planned | CI builds and validates the native ARMv4T/musl feed; on hardware verify `opkg update`, install/remove/reinstall, dependency handling, `/etc` conffile preservation, available-space failure and interrupted-transaction recovery. Cryptographic repository signing remains a separate release gate. |
| Graphical session | Experimental | The image includes the Matchbox session (TinyX, launcher, panel and on-screen keyboard); verify QVGA startup, stylus, physical navigation, idle RAM and clean exit on the device. |

## Regression record

`0.1.14-engineer` is known bad on physical RX1950 hardware. It reaches the
kernel and panics during root mounting with:

```
VFS: Unable to mount root fs on unknown-block(179,2)
```

The corresponding published image was inspected after the report: its MBR,
second-partition offset/size, ext4 magic, ext4 feature flags and clean-state
match the booting 0.1.13 image. The regression was therefore introduced by the
kernel-side experimental peripheral changes. The direct S3CMCI CD/WP
control-flow change is reverted, the RX1950 DMA platform device is removed from
the early board path, and optional hwmon registration is isolated from the
rollback-prone core platform-device array.

## Sources and verification record

The published HP specification identifies the S3C2442, 32 MiB RAM, 64 MiB ROM,
QVGA display, SD/SDIO/MMC slot, 802.11b WLAN, removable 1100 mAh battery,
infrared, USB/serial dock connector and audio interfaces. The historical
upstream board file enumerates the platform devices, GPIO key map, UDA1380
codec, MCI wiring, framebuffer/backlight, RTC, USB device controller, NAND,
battery and LEDs. The kernel configuration selects the corresponding in-tree
drivers as built-ins, so the image does not depend on an unshipped module tree
for its boot-critical hardware. The engineering kernel exposes the S3C2442 ADC
through hwmon while retaining the existing battery driver; raw ADC channels
remain available for board investigation. The TI WLAN path is an explicit
optional-module exception: a pinned ACX100 slave-memory port and RX1950 glue are
now built and validated by CI, but remain **Planned** until the radio is detected
and exercised on the physical handheld. Proprietary TI firmware is never
bundled in the release image. The Linux Kernel Driver Database records the
in-tree machine configuration through Linux 6.2.

Primary references:

- HP, [iPAQ rx1950 specifications](https://support.hp.com/cn-zh/document/c01203014)
- Linux, [historical rx1950 board support](https://code.googlesource.com/linux/torvalds/linux/+/18ded910b589839e38a51623a179837ab4cc3789/arch/arm/mach-s3c24xx/mach-rx1950.c)
- Linux Kernel Driver Database, [`CONFIG_MACH_RX1950`](https://cateee.net/lkddb/web-lkddb/MACH_RX1950.html)

Each release adds dated results, kernel revision, card model and test notes to
this section. A missing result is a failed release gate, not implicit support.

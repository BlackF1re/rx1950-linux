# Hardware support matrix

Status is deliberately conservative. **Planned** means the board support or
published specifications identify the hardware, but this project has not yet
recorded a passing test on an rx1950. **Experimental** means it has booted or
been detected but lacks the release test suite. Only **Supported** may appear
in a release claim.

For the lower-level physical inventory — including hardware that exists but is
not yet usable, unresolved board components, and features known to be absent —
see [the RX1950 hardware inventory](hardware-inventory.md). The two documents
use different axes intentionally: this file records release qualification,
while the inventory records physical existence and Linux implementation state.

## Platform and interactive hardware

| Subsystem | Known implementation | Status | Required release test |
| --- | --- | --- | --- |
| CPU and memory | Samsung S3C2442, 300 MHz ARM920T/ARMv4T; 32 MiB SDRAM; debug boot overhead removed and 12 MiB `lzo-rle` zram tier configured | Experimental | Linux 6.2 sees all 32 MiB physical RAM and reports 25,344 KiB after the kernel's own code/data/reserved pages. The remaining gap is not missing RAM that can safely be handed to userspace. Re-test idle/peak GUI memory, swap effectiveness and sustained pressure. |
| Internal flash | 64 MiB ROM / NAND, reserved for Windows Mobile; all four partitions are kernel read-only and `mtdblock` is disabled | Protected | Confirm the candidate emits no automatic NAND reads/ECC noise and that writes through every `/dev/mtd*` character device fail with `EROFS`. |
| SD/MMC/SDIO | S3C24xx MCI; 1-bit/4-bit SD, MMC and SDIO slot | Experimental | Boot-tested on 0.1.13; re-verify cold boot, read/write/remount, card-detect and write-protect after the 0.1.14 regression rollback. |
| LCD | 3.5-inch transflective 65k-colour QVGA TFT; S3C24xx framebuffer and modular Xorg/fbdev | Experimental | Native 240x320 X/Matchbox is physically verified on 0.1.19; still verify long-running redraw and recovery after suspend. |
| Backlight | PWM-controlled panel backlight | Experimental | Brightness control is verified on hardware; still verify blank/unblank and recovery after suspend. |
| Touchscreen | SoC ADC/resistive single-touch controller; evdev affine transform derived from five physical measurements | Experimental | Axis direction is physically verified on 0.1.19. Verify the candidate's fitted edge reach, centre residual, drag, wake input and persistence; `xinput_calibrator` is included for a device-specific refinement. |
| D-pad and action key | GPIO keys: up, down, left, right, enter | Experimental | Basic button input is verified; still verify every expected evdev code and graphical-session behaviour. |
| Application keys | Power, record, calendar, contacts, mail and WLAN GPIO keys | Experimental | Basic button input is verified; still verify complete mapping, long press where applicable, and non-destructive power action. |
| LEDs | Red, green and WLAN indicators on GPIO | Experimental | Manual on/off is verified on hardware; still verify triggers and safe power-state transitions. |
| RTC | S3C24xx RTC; early sanity floor plus bounded NTP correction | Experimental | 0.1.19 booted with an invalid 2037 value. Verify that the candidate replaces implausible RTC values with its build timestamp before TLS, then retains a manually/NTP-set UTC value over reset. |
| Hardware monitoring | S3C2442 ADC via separately registered `s3c-hwmon`; scaled battery voltage plus raw ADC channels 0-7 | Experimental | Run `sensors` and `rx1950-sensors`, verify stable readings alongside touchscreen/battery use, and compare battery voltage against a physical reading. |

## Connectivity and expansion

| Subsystem | Known implementation | Status | Required release test |
| --- | --- | --- | --- |
| WLAN | Integrated IEEE 802.11b TI TNETW1100B/ACX100; pinned ACX mac80211 MEM driver, verified firmware, and a signed regulatory database embedded for pre-rootfs cfg80211 startup | Experimental | Open and WPA2 association have worked on channel 7, but 0.1.19 lacked the early regulatory database and its forced boot scan could trigger ACX watchdog recovery. Verify clean boot without a forced scan, RU channels 1-13, explicit scan, both security modes, DHCP/DNS, sustained transfer and reconnect. |
| Bluetooth | No integrated controller | Not applicable | SDIO Bluetooth cards are separate optional peripherals. |
| Infrared | IrDA SIR/CIR port | Planned | `irda` stack discovery and bidirectional transfer with a known peer. |
| USB device | S3C2410 UDC via 22-pin connector; CDC-NCM Ethernet gadget, fixed recovery address, and bounded optional host-DHCP retries | Experimental | Windows 11 enumeration, `192.168.7.2`, and SSH are verified. Verify that an absent host DHCP server produces no console spam, then test lease/route/DNS plus disconnect/reconnect. |
| USB host | Connector/dock capability is not assumed | Research required | Identify electrical support before exposing a host-mode configuration. |
| Serial | Dock connector RS-232 path | Research required | Identify cable and signal levels; console transfer test after confirmation. |
| SDIO accessories | Slot supports SDIO electrically | Experimental | Each card model gets an individual driver, firmware, power and stability test. |

## Audio and power

| Subsystem | Known implementation | Status | Required release test |
| --- | --- | --- | --- |
| Audio codec | UDA1380 on I2C/I2S; playback/capture PCM and the separately registered S3C DMA provider are present; the codec reset leaves its master output muted | Experimental | The candidate explicitly initializes and unmutes named mixer controls. Verify speaker and 3.5 mm playback, volume range, underrun-free operation and SD/root stability. |
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
| Console and SSH | Experimental | Local framebuffer console and SSH over USB CDC-NCM are verified on the booting engineering image; release images intentionally use blank-root local login. Still verify reconnect and long-running stability. |
| Package management | Experimental | 0.1.19 includes `opkg 0.7.0`, but its configuration used an obsolete `lists_dir ext` directive. Verify update/install/remove/reinstall with the corrected `option lists_dir`, dependencies, conffiles, low-space and interrupted transactions. Repository signing remains a separate release gate. |
| Graphical session | Experimental | Modular Xorg/fbdev/evdev and Matchbox start successfully at QVGA on 0.1.19. Verify candidate startup, calibrated stylus, physical navigation, idle RAM, clean exit, and the separately selected PDA shell before calling it supported. |

## Regression record

### 0.1.19 on-device audit (2026-08-29)

The following observations were collected over USB SSH from the same physical
unit before preparing the next candidate. They are evidence about 0.1.19, not
claims that the replacement image has passed:

- Linux reports `MemTotal: 25344 kB`; the 12 MiB `lzo-rle` zram device is active
  and had absorbed about 5.3 MiB without an OOM during the graphical session.
- Xorg, fbdev, evdev and Matchbox run at 240x320. Touch axes are correct after
  manual calibration, but the old transform does not reach the display edges.
- ALSA card 0 exposes one UDA1380 duplex PCM with playback and capture. Opening
  playback succeeds; mixer initialization/output unmute was missing.
- cfg80211 loads its built-in signing certificate before the SD root is mounted,
  then fails to find `regulatory.db`; the resulting domain remains `00`.
- the forced WLAN boot scan reaches the ACX watchdog/recovery path. The radio
  is therefore brought up without scanning in the replacement image; scanning
  remains an explicit operation that must pass physical acceptance.
- `usb0` and SSH at `192.168.7.2` are stable, while an always-running `udhcpc`
  repeatedly broadcasts when the host provides no DHCP service.
- both system time and the hardware RTC reported 2037-05-09. The replacement
  image only corrects values outside a conservative build-time window.
- `opkg 0.7.0` rejects the obsolete `lists_dir ext` syntax used by 0.1.19.
- automatic `mtdblock` probing read all internal partitions and logged five
  uncorrectable ECC errors. No write was attempted; the replacement removes
  the block frontend and masks every partition read-only.

Battery data remains unresolved: the driver reported `Full` while
`voltage_now` was about 2.97 V and its current/charge fields were zero. Changing
the ADC scale or charge tables without an external voltage measurement would
turn an uncertain reading into a fabricated one, so physical calibration is a
release gate rather than an unverified source change.

### Historical storage regression

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

## WLAN physical trace record

The first ACX100 hardware bring-up on the current engineering system proved the
board-level path before the driver fix was written:

- MMIO `0x20000000` responded and the driver identified ACX100/TNETW1100B;
- EEPROM/config reported form factor `0x03`, radio type `0x0d` Maxim MAX2820,
  firmware `Rev 1.9.8.b` and station MAC `00:09:2d:a6:34:66`;
- `WLANGEN.BIN` and `RADIO0d.BIN` uploaded and validated successfully;
- `wlan0` was registered and EINT16/IRQ64 delivered a real `RX_DATA` cause;
- the old merged PCI/MEM top-half then masked all ACX interrupts and deferred
  processing without ACKing the MEM cause. Synchronous command polling started
  before the worker ran, remained stuck on `irq bits:0x01`, and timed out;
- the first immediate-ACK fix also consumed `HOST_INT_CMD_COMPLETE` in hard IRQ,
  racing the driver's synchronous command poller. The corrected patch leaves
  command completion to that poller while deferring data IRQs; a second patch
  cancels a firmware scan before interface teardown and reports completion
  exactly once. Physical scan/association acceptance remains required.

This evidence rules out the earlier broad hypotheses of missing WLAN power,
wrong MMIO address, missing firmware and a dead EINT16 line. It does not by
itself claim successful over-the-air networking with the patched module.

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
built and validated by CI, while the three ACX100 firmware payloads are bundled
only after fixed SHA-256 verification. The Linux Kernel Driver Database records
the in-tree machine configuration through Linux 6.2.

Primary references:

- HP, [iPAQ rx1950 specifications](https://support.hp.com/cn-zh/document/c01203014)
- Linux, [historical rx1950 board support](https://code.googlesource.com/linux/torvalds/linux/+/18ded910b589839e38a51623a179837ab4cc3789/arch/arm/mach-s3c24xx/mach-rx1950.c)
- Linux Kernel Driver Database, [`CONFIG_MACH_RX1950`](https://cateee.net/lkddb/web-lkddb/MACH_RX1950.html)

Each release adds dated results, kernel revision, card model and test notes to
this section. A missing result is a failed release gate, not implicit support.

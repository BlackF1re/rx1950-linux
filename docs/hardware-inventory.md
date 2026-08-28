# RX1950 hardware inventory

This document is the living hardware inventory for the HP iPAQ rx1950. It is
intentionally stricter than a marketing specification: hardware moves between
sections only when the evidence changes.

The inventory is maintained alongside the distribution. When a subsystem is
brought up, validated on physical hardware, or disproved by board inspection,
its row must be moved rather than duplicated.

Classification rules:

- **Known and supported** — the hardware is known to exist and Linux currently
  exposes or uses it through the appropriate subsystem. For board-specific
  peripherals, physical-device evidence is preferred over compilation alone.
- **Known, not yet fully supported** — the hardware is known to exist, but the
  Linux path is incomplete, unvalidated on the handheld, or missing a required
  feature.
- **Possible / unresolved** — the SoC contains the block or the board strongly
  implies a component, but its exact routing, part number or availability on
  the rx1950 PCB is not yet established.
- **Known absent** — the standard rx1950 does not contain the feature. External
  SDIO, USB or dock accessories are separate peripherals and do not change the
  onboard-hardware classification.

The separate [hardware support matrix](hardware.md) remains the release-facing
acceptance record. This file is the lower-level engineering inventory from
which that matrix is derived.

## 1. Known and supported

| Component | Hardware implementation | Linux exposure / evidence |
| --- | --- | --- |
| CPU | Samsung S3C2442 / ARM920T, ARMv4T, 300 MHz | Active CPU platform; system boots and runs userspace. |
| MMU and CPU caches | ARM920T MMU, 16 KiB I-cache, 16 KiB D-cache | Used by the ARM kernel. |
| SDRAM | 32 MiB mobile SDRAM | Used as system RAM and reported by Linux. |
| Interrupt controller | S3C24xx interrupt controller plus external EINT lines | Active kernel IRQ subsystem. |
| GPIO controller | S3C24xx GPIO banks GPA through GPJ | Board devices use the GPIO controller; occupied GPIOs are owned by their drivers. |
| Main clock / PLL platform | S3C2442 clock tree with 16.934 MHz board reference | Kernel initializes the S3C2442 clocks from 16,934,000 Hz. |
| System timers | S3C24xx timer block | Provides kernel timing / clockevent functionality. |
| LCD controller | S3C24xx TFT framebuffer controller | `/dev/fb0`; physically verified display output. |
| LCD panel | 3.5-inch 240x320 QVGA TFT, RGB565 / 16 bpp | Native 240x320 framebuffer is working on the handheld. |
| LCD power sequencing | Board GPIO sequencing around the TFT panel | Working together with display blank/unblank and backlight control. |
| Backlight | PWM-controlled backlight, GPB0 / TOUT0 | `/sys/class/backlight`; brightness control physically verified. |
| Resistive touchscreen | S3C ADC touchscreen interface | Linux input/evdev; touch physically verified. |
| Touch ADC configuration | Prescaler 49, delay 10000, 8x oversampling | Used by the S3C touchscreen driver. |
| 8-channel 10-bit ADC | S3C2442 ADC0-ADC7 | Raw ADC0-ADC7 are readable through the hwmon path. |
| ADC0 | Main-battery voltage channel | Exposed as scaled `in0_input` / `main-battery`; physically observed around 4.17 V. |
| S3C hwmon path | S3C ADC via separately registered `s3c-hwmon` | `sensors` and raw `adc0_raw` ... `adc7_raw` are available. |
| Main battery voltage | ADC0 with board scale factor | `power_supply` and hwmon agree closely on battery voltage. |
| Main battery state model | S3C ADC battery driver with RX1950 charge/discharge LUTs | Exposed through `/sys/class/power_supply/main-battery`. |
| Green LED | GPA6 | Linux LED class; manual control physically verified. |
| Red LED | GPA7 | Linux LED class; manual control physically verified. |
| Blue LED line | GPA11 | Linux LED class; manual control exists. The line is also part of the historical WLAN power design, so independent use remains subject to WLAN hardware validation. |
| Hardware LED blink support | GPA3 / GPA4 / GPJ6 assist the board blink circuit | Driven through the RX1950 GPIO LED callback rather than exported as free GPIOs. |
| Power button | GPF0, active-low, wake-capable | `gpio-keys`, `KEY_POWER`; physical key input verified. |
| Record button | GPF7 | `gpio-keys`, `KEY_F5`; physical key input verified. |
| Calendar button | GPG0 | `gpio-keys`, `KEY_F1`; physical key input verified. |
| Contacts button | GPG2 | `gpio-keys`, `KEY_F2`; physical key input verified. |
| Mail button | GPG3 | `gpio-keys`, `KEY_F3`; physical key input verified. |
| WLAN hardware button | GPG7 | `gpio-keys`, `KEY_F4`; input side supported independently of radio bring-up. |
| D-pad Left | GPG10 | `KEY_LEFT`; physical button path verified. |
| D-pad Right | GPG11 | `KEY_RIGHT`; physical button path verified. |
| D-pad Up | GPG4 | `KEY_UP`; physical button path verified. |
| D-pad Down | GPG6 | `KEY_DOWN`; physical button path verified. |
| D-pad center / action | GPG9 | `KEY_ENTER`; physical button path verified. |
| SD/MMC controller | S3C24xx SDI / MCI | Root filesystem runs from SD; controller is physically verified. |
| SD card-detect | GPF5, active-low | Owned by the MMC driver. |
| SD write-protect input | GPH8, active-low | Wired into the MMC platform data. |
| SD bus | GPE5-GPE10 multiplexed for SD clock/cmd/data | Working storage path. |
| SD power control | Board-specific MCI power callback | Used by the active SD path. |
| Linux root on SD | `/dev/mmcblk0p2` | Cold boot and full-card root expansion have been physically verified. |
| USB 1.1 device controller | S3C2410-compatible UDC in S3C2442 | Active USB gadget controller. |
| USB VBUS detect | GPG5, active-low | Used by the UDC. |
| USB D+ pull-up | GPJ5, active-high | Used by the UDC connect/disconnect path. |
| CDC-NCM USB networking | USB gadget over the 22-pin connector | Physically verified; used for SSH/recovery networking. |
| I2C controller 0 | S3C IIC controller | `/dev/i2c-0` and `/sys/bus/i2c`; physically verified by the bound codec. |
| UDA1380 control interface | Philips/NXP UDA1380 at I2C address `0x1a` | Codec binds successfully to `uda1380-codec`; register/control bus path is alive. |
| UDA1380 power line | GPJ0 | Defined in codec platform data. |
| UDA1380 reset line | GPD0 | Defined in codec platform data. |
| I2S pinmux | GPE0-GPE4 | Configured for the S3C24xx IIS interface. PCM operation is tracked separately below. |

## 2. Known hardware not yet fully supported or validated

This section includes hardware for which some driver code may already exist.
"Not yet fully supported" means the complete physical-device acceptance path is
still missing.

| Component | What is known to exist | Missing work / acceptance requirement |
| --- | --- | --- |
| Integrated WLAN | TI TNETW1100B / ACX100, IEEE 802.11b | Driver and RX1950 glue are built as isolated modules, but the radio still needs physical firmware probe, scan, association, DHCP and sustained-transfer validation. |
| WLAN RF section | ACX100-compatible RF transceiver and onboard antenna | Read the real radio ID and identify the RF part; verify transmit/receive operation. |
| WLAN memory window | Historical slave-memory ACX mapping at `0x20000000` | Confirm normal register access on physical hardware. |
| WLAN IRQ | GPG8 / EINT16 | Confirm interrupt delivery under scan and traffic. |
| WLAN reset | GPA14 | Confirm reset sequencing on the handheld. |
| WLAN chip-select | GPA15 / nGCS4 | Confirm external-bus access and ownership. |
| WLAN clock | GPH10 / CLKOUT1 | Confirm required clock output and stable radio operation. |
| WLAN auxiliary lines | GPC8 and GPC9, asserted by the historical RX1950 WLAN code | Confirm their electrical role and required state. |
| WLAN power / Blue coupling | GPA11 is both the Blue LED GPIO in mainline RX1950 support and `WLAN_POWER_PIN` in historical ACX board glue | Determine whether WLAN can remain powered with Blue independently controlled; keep `no-gpa11-power` as a diagnostic mode until proven. |
| WLAN firmware | Proprietary TI ACX100 firmware | Import externally, do not redistribute without a clear licence; capture exact filenames/radio ID required by the real unit. |
| Audio PCM playback | UDA1380 + S3C I2S + headphones/speaker | PCM is blocked by the unresolved safe S3C2442 DMA activation path. |
| Audio capture | UDA1380 + integrated microphone | Requires the same working PCM/DMA path, then capture/gain/noise tests. |
| S3C2442 audio DMA | SoC DMA hardware exists | Reintroduce DMA without putting experimental registration into the boot-critical RX1950 platform-device path. |
| Built-in speaker | UDA1380 speaker route with board power control | Validate playback, level and power sequencing after DMA is fixed. |
| Speaker power line | GPA1 | Validate the real amplifier/power stage through ASoC DAPM. |
| Headphone output | 3.5 mm jack connected to UDA1380 headphone outputs | Validate stereo playback and route switching. |
| Headphone detect | GPG12, inverted, 200 ms debounce in the RX1950 machine driver | Physically validate insertion/removal and automatic route state. |
| Integrated microphone | Mono microphone routed to UDA1380 VINM | Validate recording and gain. |
| Internal NAND | 64 MiB NAND / ROM storage | Enumerate and inspect read-only first; preserve Windows Mobile and do not write boot partitions during bring-up. |
| NAND partition map | Historical `Boot0`, `Boot1`, `Kernel`, `Filesystem` layout | Confirm actual device IDs/layout before any write support is considered. |
| NAND ECC path | S3C NAND controller with software ECC in historical board data | Validate read integrity and bad-block handling. |
| RTC | S3C24xx RTC | Test read/set, retention across reset and system-clock restore. |
| RTC alarm / wake | S3C RTC alarm capability | Test wake from suspend and alarm persistence. |
| Watchdog | S3C24xx watchdog | Perform a deliberate reset only on a disposable test image; document recovery. |
| AC / charger cable transitions | GPF2 / EINT2 external-power detect | Driver exists; physically verify unplug/replug transitions and event propagation. |
| Charge-status input | GPF3 | Verify charging/full transitions against real charger behaviour. |
| Charger enables | GPJ2 and GPJ3 | Validate safe enable/disable semantics and ensure userspace cannot accidentally bypass the power driver. |
| ADC1 | Historical board data labels it the battery-current channel | `adc1_raw` has been observed as zero; identify whether current sensing is functional and derive correct units. |
| ADC2 | ADC channel exists and returns data | Electrical function unknown; correlate against power, touch, WLAN, audio and temperature changes. |
| ADC3 | ADC channel exists and returns data | Electrical function unknown. |
| ADC4 | ADC channel exists | Electrical function unknown. |
| ADC5 | ADC channel exists | Electrical function unknown. |
| ADC6 | ADC channel exists and has been observed near full scale | Electrical function unknown. |
| ADC7 | ADC channel exists and has been observed near full scale | Electrical function unknown. |
| IrDA / SIR port | Physical infrared port; UART2 is configured as the IR UART in the historical board file | Identify external transceiver control and provide a usable bidirectional IR path. |
| UART0 | S3C UART0 | Determine its board routing and intended external/debug role; expose safely where physically accessible. |
| UART1 | S3C UART1 | Determine routing and intended role. |
| UART2 | S3C UART2, historically the IR port | Raw UART exists in the SoC; complete the IrDA/transceiver integration. |
| RS-232 over HP connector | HP documented a serial cable/path on the 22-pin connector | Determine which UART and level-shifting path are used, then validate with the correct cable. |
| Complete 22-pin connector map | Physical HP sync/charge connector | Document every pin, voltage domain and multiplexed function; expose only proven safe interfaces. |
| SDIO peripheral mode | Slot is electrically SDIO-capable | Validate actual SDIO cards, interrupt/power behaviour and drivers beyond plain SD storage. |
| Suspend / resume | S3C24xx PM support and RX1950 board restore code exist | Repeatedly validate SD/root integrity, LCD/backlight, touch, WLAN, buttons and USB recovery across suspend/resume. |
| Wake sources | Power key and selected external interrupts are wake-capable | Test and document each intended wake source. |
| Soft-reset switch | Physical reset control exists | Document the board reset path; it is not expected to become a normal userspace input device. |

## 3. Possible, unresolved or board-level components

These items must not be advertised as supported until the physical board or
runtime evidence proves them. A SoC-integrated peripheral is listed here when
Samsung provides the block but HP routing is unknown.

| Possible component / capability | Why it is plausible | How to resolve it |
| --- | --- | --- |
| Exact WLAN RF transceiver | ACX100 requires an external/companion RF section | Read ACX radio ID and inspect PCB markings. |
| MAX2820 or related ACX100 RF part | Common historical pairing for some ACX100 radio IDs | Do not assume; confirm by radio ID or chip marking. |
| Exact WLAN NVS / EEPROM arrangement | ACX firmware/radio configuration requires persistent board data somewhere in the design | Inspect driver diagnostics and board traces/components. |
| Battery charger IC | GPJ2/GPJ3 clearly control a charging circuit | Identify the power IC on both sides of the PCB and trace status/control pins. |
| Battery current-sense amplifier / shunt | ADC1 is designated as battery current in historical platform data | Trace ADC1 electrically and inspect the battery/power area. |
| Battery temperature sensing | Battery packs/power circuits often expose a thermistor or thermal input | Inspect battery connector pins and correlate ADC2-ADC7 with temperature. |
| Separate temperature sensor | Not documented, but could exist in the power subsystem | Search board markings and buses; do not create a Linux temperature channel without evidence. |
| Main PMIC or multiple discrete regulators | 1.8 V, 3.3 V and analogue/display rails necessarily exist | Produce a rail map and identify each regulator; model controllable rails with Linux regulator framework where useful. |
| 1.8 V regulator | Required by SC32442/memory domains | Identify part and consumers. |
| 3.3 V regulator | Required by I/O, SD and likely WLAN domains | Identify part, enable GPIO and consumers. |
| LCD bias / panel power converter | TFT panel requires board-level power electronics | Trace LCD connector rails and identify the driver circuitry. |
| Backlight driver transistor / IC | GPB0 PWM must drive an external light-power stage | Trace GPB0 and identify the switching/driver part. |
| Speaker amplifier IC | GPA1 controls an external speaker-power path | Trace UDA1380 outputs and GPA1 to the speaker section. |
| Audio analogue switch / mux | Could be used around speaker/headphone routing | Inspect the jack/audio section and verify against ASoC routing. |
| Exact IrDA transceiver IC | The infrared function is physically present but the external transceiver part is not documented in current project sources | Read PCB marking and trace UART2/control signals. |
| USB / RS-232 level or analogue interface ICs | The 22-pin connector supports multiple electrical functions | Inspect components between SoC and connector. |
| USB host routing | S3C2442 contains a USB host controller | Trace whether host D+/D- and power switching reach the 22-pin connector or any test pads. |
| USB host VBUS power switch | Required if HP actually routed host mode | Inspect power-path components around the connector. |
| SPI0 board connection | SPI0 exists inside S3C2442 | Trace pins/test pads; enumerate only if a real consumer exists. |
| SPI1 board connection | SPI1 exists inside S3C2442 | Same as SPI0. |
| Camera-interface routing | S3C2442 contains a camera interface even though RX1950 has no camera | Check whether any interface pins reach test pads or remain unconnected. |
| AC97 routing | S3C2442 includes AC97 capability while RX1950 audio uses I2S/UDA1380 | Inspect pin use; likely unused, but do not assert until mapped. |
| Free GPIOs | Not every S3C2442 GPIO is consumed by known RX1950 devices | Build a complete GPA-GPJ ownership map from board code plus physical tracing before exposing any as general-purpose GPIO. |
| Test pads | Production PDA boards commonly expose manufacturing/debug pads | Photograph both PCB sides and map pads by continuity/boot observation. |
| JTAG pads | ARM920T provides JTAG/EmbeddedICE and historical RX1950 recovery work used low-level debug | Locate and document TCK/TMS/TDI/TDO/nTRST/reset/ground. |
| UART debug pads | At least some UART routing may be available internally | Probe candidate pads safely with a logic analyser/oscilloscope. |
| Free ADC inputs | ADC2-ADC7 are readable, but their external connections are unknown | Correlate raw values under controlled hardware state changes, then trace PCB nets. |
| Free PWM/timer channels | S3C2442 has multiple timer/PWM channels and only known consumers use a subset | Audit ownership before exposing any generic PWM channel. |
| Exact LCD panel model/revision | Replacement references exist but do not prove the factory panel fitted to every RX1950 | Read the label on the actual LCD module and connector. |
| Exact SDRAM/NAND die revision | SC32442 was offered with stacked-memory variants | Read NAND ID and inspect any available silicon/package identification. |
| Board revision differences | HP may have shipped more than one PCB or component revision | Record PCB revision, component markings and hardware behaviour per tested unit. |
| Additional power-good / reset supervisor circuitry | Portable devices normally contain reset/power supervision beyond the SoC | Inspect power/reset area and map any GPIO/EINT connections. |
| Level shifters / analogue switches | Likely around connector, audio and IR domains | Identify parts and determine whether any require kernel-controlled enable lines. |
| ESD / connector protection devices | Expected around external interfaces | Document in a physical BOM; normally no Linux representation is required. |

## 4. Known absent from the standard rx1950

This is intentionally the least operationally useful table, but it prevents
future work from accidentally treating a feature from another iPAQ model or an
external accessory as onboard RX1950 hardware.

| Feature | Status / note |
| --- | --- |
| Integrated Bluetooth controller | Absent from the standard rx1950. |
| Integrated GPS / GNSS receiver | Absent. GPS navigator bundles used external accessories, not an onboard receiver. |
| GSM / EDGE / UMTS / LTE modem | Absent. |
| SIM interface | Absent. |
| Integrated camera | Absent. The SoC camera-interface block does not imply a camera on the board. |
| Cellular antenna / RF chain | Absent. |
| Capacitive touchscreen | Absent; the rx1950 uses a resistive touchscreen. |
| Multitouch controller | Absent. |
| 3D GPU / graphics accelerator | Absent. Display output is handled by the S3C framebuffer controller. |
| ARM VFP / hardware floating-point unit | Absent on ARM920T; the distribution uses the soft-float ABI. |
| 5 GHz WLAN | Absent; onboard WLAN is 2.4 GHz 802.11b. |
| 802.11n WLAN | Absent. |
| 802.11ac WLAN | Absent. |
| 802.11ax WLAN | Absent. |
| NFC controller / antenna | Absent. |
| Gyroscope | Absent from the standard documented platform. |
| Magnetometer | Absent from the standard documented platform. |
| Barometer | Absent from the standard documented platform. |
| Proximity sensor | Absent from the standard documented platform. |
| Hardware QWERTY keyboard | Absent. Text entry requires the touchscreen/onscreen keyboard or an external accessory. |
| Integrated Ethernet PHY / RJ45 | Absent. Networking is via WLAN, USB gadget, or external accessories. |
| SATA controller / connector | Absent. |
| PCI / PCIe expansion bus | Absent from the usable RX1950 platform. |

Accelerometer and ambient-light/temperature sensing are deliberately **not**
placed in this table yet: they have not been identified in the standard board
documentation, but the unresolved ADC and board-level analogue inventory is not
complete enough to turn lack of evidence into a definitive hardware absence.

## Maintenance workflow

When new evidence is obtained:

1. Record the physical observation or kernel/user-space test in the relevant
   bring-up notes.
2. Update the row here, moving it between sections if its confidence changes.
3. Update [hardware.md](hardware.md) if the release-facing support state changes.
4. Add or strengthen CI/source contracts when the result can be checked without
   the handheld.
5. Never promote a peripheral solely because its driver compiled; electrical
   validation on an actual rx1950 is required for board-specific hardware.

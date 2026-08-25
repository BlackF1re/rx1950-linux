# Hardware support matrix

## Platform

| Feature | Target |
| --- | --- |
| CPU | Samsung S3C2442 ARM920T |
| Memory | Internal RAM and SD based storage |
| Boot | HaRET SD boot |
| Display | TFT LCD framebuffer |
| Input | Resistive touchscreen |
| Storage | SD/MMC |
| Audio | S3C24xx audio with UDA1380 support |
| Network | Integrated wireless adapter |
| Power | Battery monitoring and suspend/resume |

## Driver priorities

### First stage

- kernel boot
- framebuffer console
- storage
- input

### Second stage

- wireless networking
- audio
- battery information
- suspend/resume

### Third stage

- graphical environment
- hardware acceleration research
- additional peripherals

Firmware components will be documented separately when their exact hardware requirements are confirmed.

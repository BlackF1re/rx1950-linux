# Linux kernel integration

Kernel build layer for HP iPAQ rx1950.

Target features:

- Samsung S3C2442
- framebuffer
- touchscreen
- MMC/SD
- audio
- power management

## Boot probe patch

`patches/0001-rx1950-add-early-led-boot-markers.patch` is applied to the
pinned Linux 6.2 source before every build. It is intentionally temporary:
the first physical boot has neither a usable LCD nor a serial cable, so the
machine callbacks expose their progress through the built-in LEDs. It must not
be retained in a release that claims normal power and LED behaviour.

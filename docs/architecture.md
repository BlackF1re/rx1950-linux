# rx1950-linux architecture

## Boot flow

```
HP bootloader
  |
  +-- no SD card -> Windows Mobile 6.1
  |
  +-- SD card -> HaRET -> Linux kernel -> rootfs
```

## Planned stack

Kernel:
- ARM Linux kernel with rx1950 machine support
- framebuffer
- touchscreen
- SD/MMC
- battery
- audio

Userspace:
- Buildroot/OpenEmbedded based rootfs
- BusyBox
- opkg
- Dropbear
- Python 3
- htop

## Image

Final releases will be raw SD images usable by Rufus.

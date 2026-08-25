# rx1950-linux

Modern lightweight Linux distribution for HP iPAQ rx1950.

## Goals

- Boot from SD card without modifying Windows Mobile 6.1
- Modern embedded Linux userspace
- Small reproducible builds
- Package management
- htop, Python 3, SSH and framebuffer support

## Architecture

```
SD card
├── FAT32
│   ├── haret.exe
│   ├── default.txt
│   └── zImage
└── Linux rootfs
    ├── BusyBox
    ├── opkg
    ├── Python 3
    └── applications
```

## Hardware target

- HP iPAQ rx1950
- Samsung S3C2442 ARM920T
- 240x320 LCD
- Resistive touchscreen
- SD boot via HaRET

## Build

GitHub Actions produces a raw SD image artifact suitable for writing with Rufus.

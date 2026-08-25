# Architecture

## Boot model

The initial target is a non-destructive SD card boot flow.

```
HP iPAQ boot firmware
        |
        v
Windows Mobile 6.1
        |
        v
HaRET
        |
        v
Linux kernel
        |
        v
Linux root filesystem on SD card
```

The internal device software remains available when the SD card is removed.

## System layers

### Boot layer

Responsible for loading Linux without modifying internal firmware.

Components:

- HaRET configuration
- kernel image
- boot parameters
- SD card layout

### Kernel layer

Targets the existing ARM S3C24xx Linux support:

- Samsung S3C2442 platform
- LCD controller
- touchscreen input
- SD/MMC
- audio subsystem
- power management
- device drivers

### Userspace layer

The distribution is designed as an embedded Linux system with:

- small memory footprint
- reproducible builds
- package installation
- remote administration
- optional graphical stack

## Build output

The final artifact is a raw SD card image:

```
rx1950-linux.img
```

This image can be written directly to an SD card.

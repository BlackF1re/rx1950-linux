# rx1950-linux

Modern lightweight Linux distribution for HP iPAQ rx1950.

## Project goal

rx1950-linux aims to provide a complete, reproducible Linux distribution for the HP iPAQ rx1950 while preserving the original Windows Mobile 6.1 installation. The primary boot path uses an SD card and leaves the internal firmware untouched.

The target is a practical pocket Linux computer with:

- SD card boot through the existing boot chain
- Linux kernel with rx1950 hardware support
- framebuffer display support
- touchscreen input
- power management
- wireless networking
- sound support
- SSH access
- package management
- Python 3 runtime
- command line and lightweight graphical environments

## Hardware target

| Component | Target |
| --- | --- |
| Device | HP iPAQ rx1950 |
| SoC | Samsung S3C2442 |
| CPU | ARM920T ARMv4T |
| Display | 240x320 TFT LCD |
| Input | Resistive touchscreen |
| Storage | SD card root filesystem |
| Boot | HaRET based SD boot |
| Firmware | Windows Mobile 6.1 preserved |

## Build architecture

```
SD image
├── FAT boot partition
│   ├── HaRET loader
│   ├── kernel image
│   └── boot configuration
│
└── Linux root filesystem
    ├── base system
    ├── packages
    ├── applications
    └── user data
```

## Build system

The project uses automated GitHub Actions builds to generate a raw SD card image suitable for writing with tools such as Rufus.

## Development stages

1. Reproducible build pipeline
2. Kernel and boot image generation
3. Minimal userspace
4. Hardware enablement
5. Package repository
6. Lightweight graphical environment

## Documentation

See the `docs` directory for architecture and hardware notes.

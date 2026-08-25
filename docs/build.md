# rx1950-linux build workflow

The build pipeline will create a complete SD card image.

## Planned stages

1. Prepare ARM build environment
2. Build kernel
3. Build root filesystem
4. Install boot files
5. Generate raw SD image
6. Publish build artifact

## Image format

The generated image will contain:

- FAT boot partition
- Linux root filesystem partition
- required boot files

The resulting image is intended for direct writing using Rufus or equivalent raw image tools.

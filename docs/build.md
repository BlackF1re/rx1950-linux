# Build workflow

The build is a pinned, non-interactive pipeline that produces a raw SD-card
image and verification material. It can run from a clean checkout on Linux or
in GitHub Actions.

## Inputs

- Buildroot 2025.02.2, verified before extraction by SHA-256.
- Linux 6.2, the final upstream release containing the rx1950 machine
  description, verified before extraction by SHA-256.
- A HaRET executable downloaded over HTTPS and verified by SHA-256.
- A Buildroot external tree containing the ARM920T configuration, root overlay
  and filesystem policy.
- A fixed two-partition layout: FAT16 boot partition and ext2 root partition.

No downloaded source or executable is used until its recorded checksum matches.

## Pipeline

1. Validate source contracts and record the build revision.
2. Build the compact ARM920T Buildroot root filesystem with BusyBox, Dropbear,
   `opkg`, WLAN tools, ALSA command-line playback and the Matchbox handheld
   session (TinyX framebuffer server, launcher, panel and on-screen keyboard).
3. Build the boot-critical Linux 6.2 image from the rx1950-enabled configuration.
4. Verify the rootfs and kernel artifact digests before combining them.
5. Generate the HaRET FAT boot partition and assemble a 96 MiB MBR image.
6. Verify the partition geometry, checksum and exact embedded root filesystem,
   then retain provenance with the sealed payload.

The root filesystem and kernel build in parallel. The first Buildroot run
builds its hermetic ARM/musl cross-toolchain and is therefore intentionally the
longest stage. Actions caches both verified source downloads and the complete
Buildroot output directory: an unchanged configuration reuses the cross-toolchain
and built packages, while a configuration change rebuilds only its affected
targets. The image builds only the boot-critical kernel image. Unreviewed
generic modules are not compiled, shipped or installed: the stock legacy
defconfig would add more than one gigabyte of unrelated drivers to a 32 MiB
handheld image.

## Output contract

The Actions artifact and a published release contain:

- `rx1950-linux-sd.img` — raw 96 MiB SD image.
- `SHA256SUMS` — checksum of the image.
- `provenance.txt` — build revision and exact source versions.
- `zImage` and `startup.txt` — inspectable boot payload.

## Publishing

Pushes to `main` create only a sealed Actions artifact. To create a GitHub
release, run **Build & Release** manually, enable publishing and provide a
version tag. The publication job consumes the output from the same verified
assembly job; it never rebuilds the image independently.

## Hardware boundary

An assembled image does not prove that legacy hardware works on a physical
handheld. Promotion to a supported release requires the complete acceptance
record in [goals.md](goals.md) and the hardware matrix in
[hardware.md](hardware.md).

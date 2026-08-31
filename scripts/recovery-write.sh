#!/bin/sh
# Receive and verify a raw whole-card image while running entirely from RAM.

set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin

die() { echo "recovery write: $*" >&2; exit 1; }

[ "$#" -eq 2 ] || die 'usage: rx1950-recovery-write IMAGE_BYTES IMAGE_SHA256'
bytes=$1
expected=$2
case "$bytes" in ''|*[!0-9]*) die 'invalid image byte count';; esac
case "$expected" in
    *[!0-9a-fA-F]*|'') die 'invalid image SHA-256';;
esac
[ "${#expected}" -eq 64 ] || die 'invalid image SHA-256 length'

if grep -Eq '^/dev/mmcblk0(p[0-9]+)?[[:space:]]' /proc/mounts; then
    die 'an SD-card filesystem is still mounted'
fi
sectors=$(cat /sys/class/block/mmcblk0/size)
capacity=$((sectors * 512))
[ "$bytes" -le "$capacity" ] || die "image is larger than the SD card"

echo "Writing $bytes bytes to /dev/mmcblk0; do not disconnect power." >&2
dd of=/dev/mmcblk0 bs=1048576
sync

# The recovery endpoint is deliberately open on the physical USB cable; verify
# the final media independently before reporting success.
blocks=$(((bytes + 1048575) / 1048576))
actual=$(dd if=/dev/mmcblk0 bs=1048576 count="$blocks" 2>/dev/null |
    head -c "$bytes" | sha256sum | awk '{print $1}')
[ "$actual" = "$expected" ] || die "media verification failed: $actual"
echo 'RX1950_UPDATE_VERIFIED'

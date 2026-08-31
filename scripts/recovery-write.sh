#!/bin/sh
# Receive and verify a raw whole-card image while running entirely from RAM.

set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin

die() { echo "recovery write: $*" >&2; exit 1; }

render_progress() {
    phase=$1 done=$2 total=$3
    [ "$total" -gt 0 ] || return
    percent=$((done * 100 / total))
    [ "$percent" -le 100 ] || percent=100
    filled=$((percent / 5))
    empty=$((20 - filled))
    printf '\r%s %3d%% [' "$phase" "$percent" >&2
    while [ "$filled" -gt 0 ]; do printf '#' >&2; filled=$((filled - 1)); done
    while [ "$empty" -gt 0 ]; do printf '.' >&2; empty=$((empty - 1)); done
    printf ']' >&2
}

monitor_progress() {
    phase=$1 pid=$2 total=$3
    previous=-1
    progress_done=0
    while kill -0 "$pid" 2>/dev/null; do
        done=$(awk '$1 == "rchar:" { print $2; exit }' "/proc/$pid/io" 2>/dev/null || echo 0)
        case "$done" in ''|*[!0-9]*) done=0;; esac
        [ "$done" -le "$total" ] || done=$total
        progress_done=$done
        if [ "$done" -ne "$previous" ]; then
            render_progress "$phase" "$done" "$total"
            previous=$done
        fi
        sleep 1
    done
    # Do not turn a failed or zero-byte dd into a misleading 100% report.
    # The final SHA-256 comparison below remains the authoritative check.
    render_progress "$phase" "$progress_done" "$total"
    printf '\n' >&2
}

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
dd of=/dev/mmcblk0 bs=1048576 &
writer=$!
monitor_progress 'Writing   ' "$writer" "$bytes"
wait "$writer"
sync

# The recovery endpoint is deliberately open on the physical USB cable; verify
# the final media independently before reporting success.
[ $((bytes % 512)) -eq 0 ] || die 'image size is not sector aligned'
sectors=$((bytes / 512))
checksum_file=/tmp/rx1950-update.sha256
dd if=/dev/mmcblk0 bs=512 count="$sectors" 2>/dev/null |
    sha256sum > "$checksum_file" &
hasher=$!
monitor_progress 'Verifying ' "$hasher" "$bytes"
wait "$hasher"
actual=$(awk '{print $1}' "$checksum_file")
[ "$actual" = "$expected" ] || die "media verification failed: $actual"
echo 'RX1950_UPDATE_VERIFIED'

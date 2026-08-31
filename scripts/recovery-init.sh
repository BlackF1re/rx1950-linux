#!/bin/sh
# PID 1 for the rx1950 cable-update recovery.

PATH=/sbin:/bin:/usr/sbin:/usr/bin
export PATH HOME=/root

# The kernel opens this node before it invokes /init.  Keeping it in the
# initramfs, then explicitly adopting it, makes diagnostics and progress
# visible even before devtmpfs is mounted.
exec </dev/console >/dev/console 2>&1

rescue_shell() {
    echo "recovery error: $*" >/dev/tty0 2>/dev/null
    exec setsid sh -c 'exec sh </dev/tty0 >/dev/tty0 2>&1'
}

mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mount -t proc proc /proc || rescue_shell 'cannot mount proc'
mount -t sysfs sysfs /sys || rescue_shell 'cannot mount sysfs'
mkdir -p /var/run

# Recovery is deliberately unattended. If the host disappears before it can
# finish (bad cable, suspended laptop, failed SSH), return to WM and the normal
# HaRET script instead of waiting forever for somebody to press reset.
( sleep 2700; reboot -f ) &

# The updater replaces startup.txt only for this HaRET boot. Restore the normal
# script before touching the image so a failed/cancelled update remains
# recoverable with an ordinary reset.
mkdir -p /boot
mount -t vfat -o rw /dev/mmcblk0p1 /boot || rescue_shell 'cannot mount boot partition'
if [ -s /boot/startup.normal.txt ]; then
    mv /boot/startup.normal.txt /boot/startup.txt || rescue_shell 'cannot restore normal HaRET script'
    sync
fi

# Read the expected image identity before unmounting the card.  The host places
# this manifest beside the one-shot recovery kernel while normal Linux is still
# running; arbitrary USB input can therefore never select a different image.
manifest=/boot/rx1950-update.manifest
[ -s "$manifest" ] || rescue_shell 'missing update manifest'
IFS=' ' read -r image_bytes image_sha extra < "$manifest"
case "$image_bytes" in ''|*[!0-9]*) rescue_shell 'invalid update size';; esac
case "$image_sha" in *[!0-9a-fA-F]*|'') rescue_shell 'invalid update checksum';; esac
[ "${#image_sha}" -eq 64 ] && [ -z "${extra}" ] || rescue_shell 'invalid update manifest'
umount /boot || rescue_shell 'boot partition is still busy'

ip link set lo up
ip link set usb0 up || rescue_shell 'USB NCM interface is unavailable'
ip addr flush dev usb0
ip addr add 192.168.7.2/24 dev usb0 || rescue_shell 'cannot configure USB address'

# SSH has been observed to corrupt encrypted packets in this tiny ARM9
# initramfs.  Use a one-shot raw listener exclusively on the physical USB NCM
# cable instead.  The receiver validates the complete card against the manifest
# before rebooting; there are intentionally no passwords or client keys here.
echo 'rx1950 cable-update recovery ready at 192.168.7.2:31337' >/dev/tty0 2>/dev/null
while :; do
    if nc -l -p 31337 | /usr/sbin/rx1950-recovery-write "$image_bytes" "$image_sha"; then
        sync
        reboot -f
    fi
    sleep 1
done

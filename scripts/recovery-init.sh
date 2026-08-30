#!/bin/sh
# PID 1 for the rx1950 cable-update recovery.

PATH=/sbin:/bin:/usr/sbin:/usr/bin
export PATH HOME=/root

rescue_shell() {
    echo "recovery error: $*" >/dev/tty0 2>/dev/null
    exec setsid sh -c 'exec sh </dev/tty0 >/dev/tty0 2>&1'
}

mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mount -t proc proc /proc || rescue_shell 'cannot mount proc'
mount -t sysfs sysfs /sys || rescue_shell 'cannot mount sysfs'
mkdir -p /oldroot /root/.ssh /etc/dropbear /var/run

# The updater replaces startup.txt only for this HaRET boot. Restore the normal
# script before touching the image so a failed/cancelled update remains
# recoverable with an ordinary reset.
mkdir -p /boot
mount -t vfat -o rw /dev/mmcblk0p1 /boot || rescue_shell 'cannot mount boot partition'
if [ -s /boot/startup.normal.txt ]; then
    mv /boot/startup.normal.txt /boot/startup.txt || rescue_shell 'cannot restore normal HaRET script'
    sync
fi
umount /boot || rescue_shell 'boot partition is still busy'

# Reuse the installed system identity without leaving its filesystem mounted
# while the updater overwrites the card.
mount -t ext4 -o ro /dev/mmcblk0p2 /oldroot || rescue_shell 'cannot read installed rootfs'
cp /oldroot/etc/dropbear/dropbear_*_host_key /etc/dropbear/ 2>/dev/null ||
    rescue_shell 'installed Dropbear host key is missing'
cp /oldroot/root/.ssh/authorized_keys /root/.ssh/authorized_keys 2>/dev/null ||
    rescue_shell 'install a cable-update SSH key before entering recovery'
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys /etc/dropbear/dropbear_*_host_key
umount /oldroot || rescue_shell 'installed rootfs is still busy'

ip link set lo up
ip link set usb0 up || rescue_shell 'USB NCM interface is unavailable'
ip addr flush dev usb0
ip addr add 192.168.7.2/24 dev usb0 || rescue_shell 'cannot configure USB address'

dropbear -E -s -g
echo 'rx1950 cable-update recovery ready at 192.168.7.2' >/dev/tty0 2>/dev/null

while :; do
    sleep 3600
done

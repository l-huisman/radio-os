#!/usr/bin/env bash
# Runs in a privileged Ubuntu container started by image/build.sh. Unpacks the
# Ubuntu image, enlarges it, mounts it and runs image/chroot.sh inside it.
set -euo pipefail

IMAGE_SIZE=12G
work=/work
image=$work/radio-os.img.partial
target=/mnt/radio

root_loop=
boot_loop=

cleanup() {
    rm -f "$target/usr/sbin/policy-rc.d"
    if [[ -L "$target/etc/resolv.conf.radio-os" ]]; then
        mv -f "$target/etc/resolv.conf.radio-os" "$target/etc/resolv.conf"
    fi
    rm -rf "$target/tmp/radio-os"
    umount -R "$target" 2> /dev/null || true
    [[ -n "$boot_loop" ]] && losetup -d "$boot_loop" 2> /dev/null
    [[ -n "$root_loop" ]] && losetup -d "$root_loop" 2> /dev/null
    true
}
trap cleanup EXIT

partition_field() {
    local partition=$1 field=$2
    sfdisk --dump "$image" | awk -v p="$image$partition" -v f="$field" -F'[ ,=]+' \
        '$1 == p { for (i = 2; i < NF; i++) if ($i == f) print $(i + 1) }'
}

echo "==> Preparing tools"
apt-get update -qq
apt-get install -y -qq xz-utils fdisk e2fsprogs rsync > /dev/null

echo "==> Unpacking $UBUNTU_IMAGE"
xz -dc "$work/$UBUNTU_IMAGE" > "$image"

echo "==> Growing the image to $IMAGE_SIZE"
truncate -s "$IMAGE_SIZE" "$image"
echo ', +' | sfdisk --quiet --no-reread -N 2 "$image"

boot_start=$(partition_field 1 start)
boot_size=$(partition_field 1 size)
root_start=$(partition_field 2 start)

root_loop=$(losetup --find --show --offset $((root_start * 512)) "$image")
e2fsck -fy "$root_loop" || [[ $? -le 1 ]]
resize2fs "$root_loop"
boot_loop=$(losetup --find --show --offset $((boot_start * 512)) --sizelimit $((boot_size * 512)) "$image")

echo "==> Mounting"
mkdir -p "$target"
mount "$root_loop" "$target"
mkdir -p "$target/boot/firmware"
mount "$boot_loop" "$target/boot/firmware"
mount --bind /dev "$target/dev"
mount --bind /dev/pts "$target/dev/pts"
mount -t proc proc "$target/proc"
mount -t sysfs sysfs "$target/sys"
mount -t tmpfs tmpfs "$target/run"

mv "$target/etc/resolv.conf" "$target/etc/resolv.conf.radio-os"
cp /etc/resolv.conf "$target/etc/resolv.conf"
printf '#!/bin/sh\nexit 101\n' > "$target/usr/sbin/policy-rc.d"
chmod +x "$target/usr/sbin/policy-rc.d"

rsync -a --exclude build --exclude .DS_Store /radio-os/ "$target/tmp/radio-os/"

echo "==> Setting up the radio inside the image"
chroot "$target" /usr/bin/env \
    RADIO_USER_PASSWORD="$RADIO_USER_PASSWORD" RDP_USER="$RDP_USER" RDP_PASSWORD="$RDP_PASSWORD" \
    /tmp/radio-os/image/chroot.sh

cleanup
trap - EXIT
mv "$image" "$work/radio-os.img"

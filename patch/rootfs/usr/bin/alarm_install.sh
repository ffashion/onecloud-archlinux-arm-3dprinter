#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright(c) 2026 ffashion <helloworldffashion@gmail.com>
#

set -e
MAC=""
echo "Installing Archlinux arm OS to the eMMC... Please wait..."

if [ -e /dev/mmcblk0 ];then
    DEV=mmcblk0
else
    DEV=mmcblk1
fi

DEV_EMMC=/dev/${DEV}

DISK_BOOT=${DEV_EMMC}p1
DISK_ROOT=${DEV_EMMC}p2

ROOTFS=/install/rootfs
BOOTFS=/install/bootfs


# rm -f /etc/machine-id
# systemd-machine-id-setup

if [ -z "$MAC" ]; then
	MAC=$(dd if=/dev/urandom bs=1024 count=1 2>/dev/null | md5sum | sed -e 's/^\(..\)\(..\)\(..\)\(..\).*$/00:22:\1:\2:\3:\4/' -e 's/^\(.\)[13579bdf]/\10/')

	[ -f /opt/client.crt ] && {
	    MAC=$(openssl x509 -in /opt/client.crt -noout --text | grep "Subject:" | awk '{print $10}' | awk -F '[' '{print $2}' | awk -F ']' '{print $1}')
	}
fi

pre_env() {
    rm -rf $BOOTFS $ROOTFS
    install -d $BOOTFS
    install -d $ROOTFS
}


formate_disk() {
    echo "Creating MBR and partittion..."
    parted -s "${DEV_EMMC}" mklabel msdos
    parted -s "${DEV_EMMC}" mkpart primary fat32 108M 620M
    parted -s "${DEV_EMMC}" mkpart primary ext4  724M 100%

    echo -n "Formatting BOOT partition..."
    mkfs.vfat -n "alarmboot" $DISK_BOOT
    echo "done."

    echo "Formatting ROOT partition..."
    mke2fs -F -q -t ext4 -L alarmroot -m 0 $DISK_ROOT
    e2fsck -n $DISK_ROOT
    echo "done."

}

mount_disk() {
    if grep -q $DISK_BOOT /proc/mounts ; then
        echo "Unmounting BOOT partiton."
        umount -f $DISK_BOOT
    fi

    mount -o rw $DISK_BOOT $BOOTFS

    if grep -q $DISK_ROOT /proc/mounts ; then
        echo "Unmounting ROOT partiton."
        umount -f $DISK_ROOT
    fi

    mount -o rw $DISK_ROOT $ROOTFS
}

dup_disk() {
    echo "Copying ROOTFS."

    echo -n "Copying BOOT..."

    cp -r /boot/* $BOOTFS
    sync
    echo "done."

    cd /
    echo "Copying BIN..."
    tar -cf - bin | (cd $ROOTFS; tar -xpf -)

    echo "Creating DEV..."
    mkdir -p $ROOTFS/dev


    echo "Copying ETC..."
    tar -cf - etc | (cd $ROOTFS; tar -xpf -)

    echo "Copying HOME..."
    tar -cf - home | (cd $ROOTFS; tar -xpf -)

    echo "Copying LIB..."
    tar -cf - lib | (cd $ROOTFS; tar -xpf -)

    echo "Creating MEDIA..."
    mkdir -p $ROOTFS/media

    echo "Creating MNT..."
    mkdir -p $ROOTFS/mnt

    echo "Copying OPT..."
    tar -cf - opt | (cd $ROOTFS; tar -xpf -)

    echo "Creating PROC..."
    mkdir -p $ROOTFS/proc

    echo "Copying ROOT..."
    tar -cf - root | (cd $ROOTFS; tar -xpf -)

    echo "Creating RUN..."
    mkdir -p $ROOTFS/run

    echo "Copying SBIN..."
    tar -cf - sbin | (cd $ROOTFS; tar -xpf -)

    echo "Copying SRV..."
    tar -cf - srv | (cd $ROOTFS; tar -xpf -)

    echo "Creating SYS..."
    mkdir -p $ROOTFS/sys

    echo "Creating TMP..."
    mkdir -p $ROOTFS/tmp

    echo "Copying USR..."
    tar -cf - usr | (cd $ROOTFS; tar -xpf -)

    echo "Copying VAR..."
    tar -cf - var | (cd $ROOTFS; tar -xpf -)

    echo "Generate fstab..."

    BOOTFS_UUID="$(blkid -s UUID -o value ${DISK_BOOT})"
	ROOTFS_UUID="$(blkid -s UUID -o value ${DISK_ROOT})"

    printf '%s\n' \
		"UUID=$ROOTFS_UUID / ext4 defaults,noatime,nodiratime,commit=600,errors=remount-ro 0 1" \
		"UUID=$BOOTFS_UUID  /boot vfat defaults 0 2" \
		"tmpfs /tmp tmpfs defaults,nosuid 0 0" \
    > $ROOTFS/etc/fstab

    # echo "Changing MAC..."
    # cp -p $ROOTFS/etc/network/interfaces.default $ROOTFS/etc/network/interfaces
    # sed -i '/iface eth0 inet dhcp/a\hwaddress '${MAC} $ROOTFS/etc/network/interfaces

    cd /
    sync
}

function cleanup() {
    umount $BOOTFS
    umount $ROOTFS
    rm -rf /install
}

pre_env
formate_disk
mount_disk
dup_disk
cleanup

echo "*******************************************"
echo " ArchLinux arm has been installed to eMMC. Now   "
echo " you may un-plug the power cable to reboot."
echo "*******************************************"

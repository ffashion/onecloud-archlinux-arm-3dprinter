#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright(c) 2026 ffashion <helloworldffashion@gmail.com>
#

set -ev

livecd="build/livecd"

systemimg="build/system.img"
bootfs=$livecd/mnt/boot
rootfs=$livecd/mnt

export chlivedo="arch-chroot $livecd qemu-arm-static /bin/bash -c"
export chrootdo="arch-chroot $rootfs qemu-arm-static /bin/bash -c"
# export chrootdo="systemd-nspawn -D $rootfs qemu-arm-static /bin/bash -c"

export LOCALVERSION=-onecloud

function pre_build() {
    mkdir -p build
    truncate --size=4096M $systemimg

    OFFSET=16
    BOOTSIZE=256
    BOOTFS_TYPE=fat

    partition_script_output=$(
        {
            echo  "label: dos"
            echo  "1 : name=\"bootfs\", start=${OFFSET}MiB, size=${BOOTSIZE}MiB, type=ea"
            echo  "2 : name=\"rootfs\", start=$((${OFFSET} + ${BOOTSIZE}))MiB, type=83"
        }
    )

    echo "${partition_script_output}" | sfdisk ${systemimg}

    LOOP=$(losetup --show --partscan --find $systemimg)
    mkfs.fat -n alarmboot  ${LOOP}p1
    mkfs.ext4 -L alarmroot ${LOOP}p2
}

function pre_build_rootfs() {

    url="http://os.archlinuxarm.org/os/ArchLinuxARM-armv7-latest.tar.gz"
    livepack="build/ArchLinuxARM-armv7-latest.tar.gz"

    if [ ! -e $livepack ]; then
        curl -L -o $livepack $url
    fi
    mkdir -p $livecd
    # fix warnning
    mount --bind $livecd $livecd
    bsdtar -xpf $livepack -C $livecd

    cp -p /usr/bin/qemu-arm-static $livecd/bin/qemu-arm-static

    $chlivedo "sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf"
    $chlivedo "pacman-key --init"
    $chlivedo "pacman-key --populate archlinuxarm"
    $chlivedo "pacman --noconfirm -Syyu"
    $chlivedo "pacman --noconfirm -S arch-install-scripts cloud-guest-utils"
    $chlivedo "pacman --noconfirm -S base-devel git"

    mount ${LOOP}p2 $rootfs
}

function build_rootfs() {

    for package in $(cat config/*.pkg.conf); do
        sudo $chlivedo "pacstrap -cGM /mnt $package"
    done

    cp -p /usr/bin/qemu-arm-static $rootfs/bin/qemu-arm-static

    mount ${LOOP}p1 $bootfs
    # for package in $(cat config/*.aur.conf); do
    #     build_aur_package_rootfs $package
    # done
}

function post_build_rootfs() {

    umount ${LOOP}p1
    umount ${LOOP}p2

    tune2fs -M / ${LOOP}p2
    e2fsck -yf -E discard ${LOOP}p2
    resize2fs -M ${LOOP}p2
    e2fsck -yf ${LOOP}p2

    zstd $systemimg -o $systemimg.zst
}

function pre_build_linux()
{
    echo a
}

function build_linux()
{
    for file in patch/linux/*.patch; do
        patch -N -p 1 -d linux <$file
    done

    cd linux

    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- onecloud_defconfig
    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j$[$(nproc) * 2]
    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j$[$(nproc) * 2] LOADADDR=0x00208000 uImage
    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j$[$(nproc) * 2] dtbs

    cd -
}

function post_build_linux()
{
    cd linux

    make ARCH=arm INSTALL_MOD_PATH=../$rootfs modules_install
    make ARCH=arm INSTALL_HDR_PATH=../$rootfs headers_install
    make ARCH=arm INSTALL_PATH=../$bootfs install

    dtbfile=arch/arm/boot/dts/amlogic/meson8b-onecloud.dtb
    cp $dtbfile ../$bootfs

    cp -rp ../firmware ../$rootfs/usr/lib/firmware

    uimage=arch/arm/boot/uImage
    cp $uimage ../$bootfs

    cd -

    # Process uboot

    $chrootdo "echo '#KEYMAP=us' > /etc/vconsole.conf"
    $chrootdo "mkinitcpio -k 6.12.28${LOCALVERSION} -g /boot/initramfs-6.12.28.onecloud.img"

    mkimage -C none -A arm -T script -d config/uboot/boot.cmd config/uboot/boot.scr

    cp -r config/uboot/boot.cmd $bootfs
    cp -r config/uboot/boot.env $bootfs
    cp -r config/uboot/boot.scr $bootfs

    $chrootdo "mkimage -A arm -O linux -T ramdisk -C gzip -n uInitrd -d /boot/initramfs-6.12.28.onecloud.img /boot/uInitrd"
}

pre_build

pre_build_rootfs
pre_build_linux

build_rootfs
build_linux

post_build_linux
post_build_rootfs

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
# export chrootdo="arch-chroot $rootfs qemu-arm-static /bin/bash -c"
export chrootdo="systemd-nspawn -D $rootfs qemu-arm-static /bin/bash -c"

export LOCALVERSION=-onecloud
export KERNEL_VERSION=6.12.28
export COMMIT_ID="undefined"

function pre_build() {
    mkdir -p build
    truncate --size=8196M $systemimg

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

    COMMIT_ID=`git rev-parse HEAD `
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

function chlivealarmdo()
{
    path=$1
    chalarm="cd /home/alarm/$path && su alarm -c"
    command="$chalarm '$2'"

    $chlivedo "$command"
}

function chlive_path_do() {
    path=$1
    command="cd $path; $2"
    $chlivedo "$command"
}

function chlive_alarm_path_do() {
    chlive_path_do '/home/alarm/' "$1"
}


function build_aur_package_live()
{
    local name=$1

    local project_url="https://aur.archlinux.org/$name.git"

    result=`chlive_alarm_path_do "file $name"`

    if [[ "$result" =~ "No such file or directory" ]]; then
        chlivealarmdo "" "git clone $project_url $name"
    fi

    local runtimedeps=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${depends[@]}')
    local compiledeps=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${makedepends[@]}')
    local checkdepends=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${checkdepends[@]}')

    local pkgver=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${pkgver}-${pkgrel}')
    # local pkgarch=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${arch[@]}')

    for dep in $compiledeps; do
        if $chlivedo "pacman -Qi $dep >/dev/null 2>&1"; then
            continue;
        fi

        if ! $chlivedo "pacman -Si $dep >/dev/null 2>&1"; then
            build_aur_package_live $dep
        else
            $chlivedo "pacman --noconfirm -S $dep"
        fi
    done


    for dep in $runtimedeps; do
        if $chlivedo "pacman -Qi $dep >/dev/null 2>&1"; then
            continue;
        fi

        if ! $chlivedo "pacman -Si $dep >/dev/null 2>&1"; then
            build_aur_package_live $dep
        else
            $chlivedo "pacman --noconfirm -S $dep"
        fi
    done


    for dep in $checkdepends; do
        if $chlivedo "pacman -Qi $dep >/dev/null 2>&1"; then
            continue;
        fi

        if ! $chlivedo "pacman -Si $dep >/dev/null 2>&1"; then
            build_aur_package_live $dep
        else
            $chlivedo "pacman --noconfirm -S $dep"
        fi
    done

    result=`chlive_alarm_path_do "file $name/$name-*-*.pkg.tar.xz"`
    if [[ "$result" =~ "No such file or directory" ]]; then
        chlivealarmdo "$name" "makepkg -s --noconfirm"
    fi

    chlive_alarm_path_do "pacman --noconfirm -U $name/$name-*-*.pkg.tar.xz"

    echo "build aur packaege $name to live finished"
}

function build_package_rootfs() {
    local name=$1

    if $chrootdo "pacman -Qi $name >/dev/null 2>&1"; then
        return
    fi

    if $chrootdo "pacman -Si $name >/dev/null 2>&1"; then
        $chlivedo "pacstrap -cGM /mnt $name"
        return
    fi

    build_aur_package_rootfs $1
}

function build_package_livecd() {
    local name=$1

    if $chlivedo "pacman -Qi $name >/dev/null 2>&1"; then
        return
    fi

    if $chrootdo "pacman -Si $name >/dev/null 2>&1"; then
        $chlivedo "pacman --noconfirm -S $name"
        return
    fi

    build_aur_package_live $1
}

function build_aur_package_rootfs()
{
    local name=$1
    local project_url="https://aur.archlinux.org/$name.git"

    echo "build aur packaege $name to rootfs start"

    result=`chlive_alarm_path_do "file $name"`
    if [[ "$result" =~ "No such file or directory" ]]; then
        chlivealarmdo "" "git clone $project_url $name"
    fi

    local runtimedeps=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${depends[@]}')
    local compiledeps=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${makedepends[@]}')
    local checkdepends=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${checkdepends[@]}')

    local pkgver=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${pkgver}-${pkgrel}')
    # local pkgarch=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${arch[@]}')

    for dep in $compiledeps; do
        if $chlivedo "pacman -Qi $dep >/dev/null 2>&1"; then
            continue;
        fi

        if ! $chlivedo "pacman -Si $dep >/dev/null 2>&1"; then
            build_aur_package_live $dep
        else
            $chlivedo "pacman --noconfirm -S $dep"
        fi
    done


    for dep in $runtimedeps; do
        build_package_rootfs $dep
        build_package_livecd $dep
    done

    for dep in $checkdepends; do
        if $chlivedo "pacman -Qi $dep >/dev/null 2>&1"; then
            continue;
        fi

        if ! $chlivedo "pacman -Si $dep >/dev/null 2>&1"; then
            build_aur_package_live $dep
        else
            $chlivedo "pacman --noconfirm -S $dep"
        fi
    done

    result=`chlive_alarm_path_do "file $name/$name-*-*.pkg.tar.xz"`
    if [[ "$result" =~ "No such file or directory" ]]; then
        chlivealarmdo "$name" "makepkg -s --noconfirm"
    fi

    chlive_alarm_path_do "pacman --noconfirm -U $name/$name-*-*.pkg.tar.xz"
    chlive_alarm_path_do "pacstrap -cGMU /mnt $name/$name-*-*.pkg.tar.xz"

    echo "build aur packaege $name to rootfs finished"
}

function build_local_package()
{
    echo "build local packaege $name to rootfs start"

    cp -r pkg/$name $livecd/home/alarm/

    # FIXME: refactor me
    local runtimedeps=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${depends[@]}')
    local compiledeps=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${makedepends[@]}')
    local checkdepends=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${checkdepends[@]}')

    local pkgver=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${pkgver}-${pkgrel}')
    # local pkgarch=$(chlivealarmdo "$name" 'source PKGBUILD && echo ${arch[@]}')

    for dep in $compiledeps; do
        if $chlivedo "pacman -Qi $dep >/dev/null 2>&1"; then
            continue;
        fi

        if ! $chlivedo "pacman -Si $dep >/dev/null 2>&1"; then
            build_aur_package_live $dep
        else
            $chlivedo "pacman --noconfirm -S $dep"
        fi
    done


    for dep in $runtimedeps; do
        build_package_rootfs $dep
        build_package_livecd $dep
    done

    for dep in $checkdepends; do
        if $chlivedo "pacman -Qi $dep >/dev/null 2>&1"; then
            continue;
        fi

        if ! $chlivedo "pacman -Si $dep >/dev/null 2>&1"; then
            build_aur_package_live $dep
        else
            $chlivedo "pacman --noconfirm -S $dep"
        fi
    done

    result=`chlive_alarm_path_do "file $name/$name-*-*.pkg.tar.xz"`
    if [[ "$result" =~ "No such file or directory" ]]; then
        chlivealarmdo "$name" "makepkg -s --noconfirm"
    fi

    chlive_alarm_path_do "pacman --noconfirm -U $name/$name-*-*.pkg.tar.xz"
    chlive_alarm_path_do "pacstrap -cGMU /mnt $name/$name-*-*.pkg.tar.xz"

    echo "build aur packaege $name to rootfs finished"

}



function build_rootfs() {

    for package in $(cat config/*.pkg.conf); do
        sudo $chlivedo "pacstrap -cGM /mnt $package"
    done

    cp -p /usr/bin/qemu-arm-static $rootfs/bin/qemu-arm-static

    mount ${LOOP}p1 $bootfs

    for package in $(cat config/*.aur.conf); do
        build_aur_package_rootfs $package
    done

    build_local_package fluidd

    # Patch Rootfs file
    cp -av patch/rootfs/. $rootfs/

    export MOONRAKER_RUNTIME_HOME=/var/opt/moonraker
    $chrootdo "chown klipper: ${MOONRAKER_RUNTIME_HOME}/config/klipper.cfg"
    $chrootdo "chown klipper: ${MOONRAKER_RUNTIME_HOME}/config/moonraker.conf"

    # systemd services
    $chrootdo "systemctl enable $(cat config/services.conf)"


    $chlivedo "echo '3dprinter' > /mnt/etc/hostname"
    $chlivedo "echo 'LANG=C'> /mnt/etc/locale.conf"
    $chlivedo "echo -n > /mnt/etc/machine-id"

    # Configure rootfs
    $chrootdo "usermod -s /bin/bash klipper"
    $chrootdo "mkdir -p /home/klipper"
    $chrootdo "chown klipper: /home/klipper"
    $chrootdo "usermod -d /home/klipper klipper"

    $chrootdo "echo -e 'root:root\nklipper:klipper' | chpasswd"
    $chrootdo "usermod -a -G wheel klipper"
    $chrootdo "echo '%wheel ALL=(ALL:ALL) ALL' >> /etc/sudoers"

    $chrootdo "pacman-key --init"
    $chrootdo "pacman-key --populate archlinuxarm"

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

    uimage=arch/arm/boot/uImage
    cp $uimage ../$bootfs

    cd -

    # Process uboot

    $chrootdo "echo '#KEYMAP=us' > /etc/vconsole.conf"
    $chrootdo "mkinitcpio -k ${KERNEL_VERSION}${LOCALVERSION} -g /boot/initramfs-${KERNEL_VERSION}.onecloud.img"

    mkimage -C none -A arm -T script -d config/uboot/boot.cmd config/uboot/boot.scr

    cp -r config/uboot/boot.cmd $bootfs
    cp -r config/uboot/boot.env $bootfs
    cp -r config/uboot/boot.scr $bootfs

    $chrootdo "mkimage -A arm -O linux -T ramdisk -C gzip -n uInitrd -d /boot/initramfs-${KERNEL_VERSION}.onecloud.img /boot/uInitrd"

    echo $COMMIT_ID >> $bootfs/commit
}

function generate_checksum()
{
    systemimg_version=build/system-${KERNEL_VERSION}.img
    mv $systemimg.zst $systemimg_version.zst
    sha256sum $systemimg_version.zst > $systemimg_version.zst.sha256sum
}


pre_build

pre_build_rootfs
pre_build_linux

build_rootfs
build_linux

post_build_linux
post_build_rootfs

generate_checksum

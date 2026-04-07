# onecloud-archlinux-arm-3dprinter

## Genneral Information
1. Login Username and password

    ```user root, password root```
    ```user klipper, password klippler```
2. Supported Featured Now
    1. When System Boot, Will Startup klipper/moonraker and fluidd auto. You Can Access fluidd by onecoud ip with http
        1. klipper and moonraker from aur
        2. fluidd from github. beacause aur fluidd have some depends issue
    2. Support Can device and gs usb.
    3. Support general ISO and burn Img
        1. When use general ISO. you can use alarm_install.sh to install system to emmc
        2. alarm_install.sh allready in PATH
    4. Linux 6.12
    5. When can Device Checked. Will Start can0 set this bitrate to 500000
        1. if you want change bitrate, please edit  /usr/lib/systemd/network/60-klipper-can.network and reboot
    6. Suport GUI.
        1. use Xfce4 + Lightdm default
    7. Suport LED
        1. When Klipper Start Success. Then Led change to green

## Related Links
1. https://github.com/hzyitc/armbian-onecloud/blob/readme/.github/workflows/ci.yml
2. https://github.com/armbian/build
3. https://github.com/raysworld/onecloud-emmc-install

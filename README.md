> **Warning:** This is an experimental port. I take no responsibility for damage to any device or loss of data. Follow this guide at your own risk. Before starting, back up all data and device-specific information you can, including the exact model and variant, serial number, IMEIs, and any modem or calibration details. Keep these records securely offline; do not post them publicly. Save a stock firmware image and a recovery procedure for your exact device as well.

# Ubuntu Touch on RedMagic 7 Pro (NX709J)

This repository contains the device port sources and scripts to build and install an experimental Ubuntu Touch image for the Nubia RedMagic 7 Pro, device codename NX709J. It does not include prebuilt system images, build logs, downloaded toolchains, or machine-specific credentials.

The port has reached the Ubuntu Touch welcome/setup screen with graphics working. Touch input, Wi-Fi, cellular service, and long-term stability have not yet been confirmed. This is a development port, not an official UBports release.

## Requirements

- A Linux x86_64 build host with Git, curl, wget, tar, xz, build tools, Python 3, fakeroot, ADB, and Fastboot.
- Internet access. The first build downloads the UBports build tools, kernel source, toolchains, Ubuntu Touch rootfs, and Halium GSI.
- At least 30 GB of free disk space is recommended. Build and image outputs are large.
- A RedMagic 7 Pro (NX709J) with an unlocked bootloader and a recovery that provides ADB access. Unlocking the bootloader may erase the phone; back up anything important first.

On Ubuntu, install the common host tools with:

    sudo apt update
    sudo apt install git curl wget tar xz-utils build-essential python3 fakeroot patch adb fastboot

The image conversion step may ask for sudo access to mount a temporary loop image.

## Build

Clone this repository and run the dedicated build script:

    git clone https://github.com/DefSteam/redmagic7pro-ubuntu-touch.git
    cd redmagic7pro-ubuntu-touch
    ./scripts/build-ubuntu-touch.sh

The script pins the generic UBports build tools and the NX709J kernel source to known commits, applies the included source patches, builds the kernel and device tarball, then produces the Ubuntu Touch images. The Ubuntu Touch rootfs and Halium GSI are fetched from their upstream daily build channels, so later builds may contain updated upstream components.

The completed images are written to:

    halium-gki/images/boot.img
    halium-gki/images/rootfs.img
    halium-gki/images/system.img

Generated downloads, intermediate files, and images remain under halium-gki and are excluded from Git.

## Install

1. Back up the phone and unlock the bootloader using instructions for the exact NX709J variant. Bootloader unlocking normally factory-resets the device, so treat all data as at risk. Expect an unlocked-bootloader warning every time the phone starts. While unlocked, the phone accepts software that is not signed by its original trusted key, which reduces boot integrity protection. Some integrity-sensitive apps, DRM features, OTA updates, or warranty coverage may be affected; details vary by firmware, app, and region. See the [Android bootloader state documentation](https://source.android.com/docs/security/features/verifiedboot/device-state) and [unlocking guidance](https://source.android.com/docs/core/architecture/bootloader/locking_unlocking).

   **Do not relock the bootloader while Ubuntu Touch or other modified partitions are installed.** A locked bootloader verifies the installed software. Relocking with unsigned, mismatched, or incomplete firmware can make the phone fail verification and become unbootable, and the lock operation can erase data. Only consider relocking after restoring the complete, exact stock firmware for this device variant and following a recovery procedure verified for that firmware. A failed recovery may require a full firmware restore.

2. Obtain `vbmeta.img` from stock firmware for the exact NX709J device variant. This repository does not build or include that image.
3. Boot the phone into Fastboot and, from the directory containing `vbmeta.img`, run:

       fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img

   The Fastboot options go before `flash`.
4. Boot a recovery that mounts or can access /data and provides ADB. Connect the phone over USB.
   Make sure /data has at least 4 GB of free space for rootfs.img.
5. Run the install script from this repository:

       ./scripts/install-ubuntu-touch.sh

6. Review the confirmation prompt and type INSTALL.

The script copies rootfs.img to /data/ubuntu.img, reboots to Fastboot, checks the reported product, flashes boot.img to boot_b, and reboots. It replaces /data/ubuntu.img and boot_b; it does not erase the rest of /data. Fastboot may report `taro` on an NX709J; because that platform identifier is shared by multiple phone models, the script requires you to confirm `NX709J` before it flashes. Verify the exact model before confirming. Unknown product values or a missing confirmation stop the script before flashing. Do not use this installer for another device or variant.

Keep a copy of the phone's stock boot image and recovery procedure so you can restore Android if this experimental port does not boot. The install flow follows the Halium 9+ layout used by the device configuration: the boot image is flashed and the Ubuntu Touch rootfs image is stored in userdata. See the [UBports standalone kernel build guide](https://docs.ubports.com/en/latest/porting/build_and_boot/standalone_kernel_build.html) and [Halium installation guide](https://docs.ubports.com/en/latest/porting/build_and_boot/Halium_install.html) for background.

## Kernel configuration note

The active setting is in halium-gki/deviceinfo. It uses gki_defconfig followed by the halium-new.config fragment. The working tree previously named arch.config, but that file was absent; only arch.config.unused was present. The build script patches the pinned generic build tools to merge halium-new.config with the kernel's merge_config.sh before compiling. The boot command line also follows the NX709J Ubuntu `header-ub` settings, including the `_b` slot suffix used by the installer. The boot image header version is 4, matching the device's Android 12 boot image format.

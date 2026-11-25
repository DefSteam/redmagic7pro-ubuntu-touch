#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BOOT_IMAGE="$ROOT_DIR/halium-gki/images/boot.img"
ROOTFS_IMAGE="$ROOT_DIR/halium-gki/images/rootfs.img"

for tool in adb fastboot; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'ERROR: %s is required but was not found in PATH.\n' "$tool" >&2
        exit 1
    }
done

[ -s "$BOOT_IMAGE" ] || { printf 'ERROR: Missing image: %s\n' "$BOOT_IMAGE" >&2; exit 1; }
[ -s "$ROOTFS_IMAGE" ] || { printf 'ERROR: Missing image: %s\n' "$ROOTFS_IMAGE" >&2; exit 1; }

adb get-state >/dev/null 2>&1 || {
    printf 'ERROR: No authorized ADB device. Boot the RedMagic 7 Pro into recovery and enable ADB.\n' >&2
    exit 1
}

printf 'This installs Ubuntu Touch on a RedMagic 7 Pro (NX709J).\n'
printf 'It replaces /data/ubuntu.img and flashes boot_b. It does not wipe the rest of /data.\n'
read -r -p 'Type INSTALL to continue: ' confirmation
[ "$confirmation" = "INSTALL" ] || { printf 'Cancelled.\n'; exit 1; }

adb push "$ROOTFS_IMAGE" /data/ubuntu.img
adb reboot bootloader

printf 'Waiting for fastboot...\n'
fastboot_ready=false
for attempt in {1..30}; do
    if [ -n "$(fastboot devices)" ]; then
        fastboot_ready=true
        break
    fi
    sleep 1
done
[ "$fastboot_ready" = true ] || {
    printf 'ERROR: Fastboot device not detected. /data/ubuntu.img was copied, but boot_b was not flashed.\n' >&2
    exit 1
}

product_info="$(fastboot getvar product 2>&1 || true)"
product_value="$(printf '%s\n' "$product_info" | sed -nE 's/.*product:[[:space:]]*([^[:space:]]+).*/\1/Ip' | head -n 1)"
product_compact="${product_value,,}"
product_compact="${product_compact//[^[:alnum:]]/}"

case "$product_compact" in
    *nx709j*|*redmagic7pro*)
        ;;
    taro)
        printf 'Fastboot reports product "taro". This is a platform identifier shared by multiple phone models, so it cannot confirm NX709J by itself.\n' >&2
        read -r -p 'Verify the phone is a Nubia RedMagic 7 Pro (NX709J), then type NX709J to continue: ' model_confirmation
        [ "$model_confirmation" = "NX709J" ] || {
            printf 'ERROR: NX709J was not confirmed; refusing to flash.\n' >&2
            exit 1
        }
        ;;
    *)
        printf 'ERROR: Fastboot did not identify an NX709J RedMagic 7 Pro; refusing to flash.\n' >&2
        printf '%s\n' "$product_info" >&2
        exit 1
        ;;
esac

fastboot flash boot_b "$BOOT_IMAGE"
fastboot reboot
printf 'Install commands completed. Allow the device time to boot.\n'

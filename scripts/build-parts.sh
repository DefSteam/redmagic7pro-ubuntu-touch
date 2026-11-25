#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HALIUM_DIR="$ROOT_DIR/halium-gki"
BUILD_TOOLS_DIR="$HALIUM_DIR/build"
WORK_DIR="$HALIUM_DIR/workdir"
DOWNLOADS_DIR="$WORK_DIR/downloads"
OUT_DIR="$HALIUM_DIR/out"

usage() {
    cat <<'EOF'
Usage: ./scripts/build-parts.sh <kernel|boot|overlay|images>

Targets:
  kernel   Recompile the kernel, then rebuild the dependent boot/device and
           Ubuntu Touch images.
  boot     Rebuild boot.img and boot-lz4.img from the cached kernel, ramdisk,
           and current deviceinfo/ramdisk-overlay settings.
  overlay  Rebuild the device archive from the current halium-gki/overlay and
           cached kernel modules, then regenerate the Ubuntu Touch images.
  images   Rebuild rootfs.img and system.img from the existing device archive.

Run ./scripts/build-ubuntu-touch.sh once first to fetch and prepare build tools,
kernel sources, and build dependencies. "header" and "ramdisk" are aliases for
the boot target.
EOF
}

die() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

if [ "$#" -ne 1 ]; then
    usage >&2
    exit 2
fi

TARGET="$1"
case "$TARGET" in
    -h|--help|help)
        usage
        exit 0
        ;;
    kernel)
        exec "$ROOT_DIR/scripts/build-ubuntu-touch.sh"
        ;;
    boot|header|ramdisk)
        TARGET=boot
        ;;
    overlay|device-overlay)
        TARGET=overlay
        ;;
    images|system)
        TARGET=images
        ;;
    *)
        usage >&2
        die "Unknown target: $TARGET"
        ;;
esac

[ -d "$BUILD_TOOLS_DIR" ] || die "Build tools are missing. Run ./scripts/build-ubuntu-touch.sh first."
[ -x "$BUILD_TOOLS_DIR/prepare-fake-ota.sh" ] || die "The cached UBports build tools are incomplete. Run ./scripts/build-ubuntu-touch.sh first."
[ -x "$BUILD_TOOLS_DIR/system-image-from-ota.sh" ] || die "The cached UBports build tools are incomplete. Run ./scripts/build-ubuntu-touch.sh first."
[ -d "$OUT_DIR" ] || die "Build output is missing. Run ./scripts/build-ubuntu-touch.sh first."

if [ "$TARGET" = boot ]; then
    [ -x "$BUILD_TOOLS_DIR/build/make-bootimage.sh" ] || die "The cached UBports build tools are incomplete. Run ./scripts/build-ubuntu-touch.sh first."
    [ -d "$DOWNLOADS_DIR/KERNEL_OBJ" ] || die "Cached kernel objects are missing. Run ./scripts/build-ubuntu-touch.sh first."
    [ -f "$DOWNLOADS_DIR/halium-boot-ramdisk.img" ] || die "Cached Halium boot ramdisk is missing. Run ./scripts/build-ubuntu-touch.sh first."
fi

if [ "$TARGET" = overlay ]; then
    [ -x "$BUILD_TOOLS_DIR/build/build-tarball-mainline.sh" ] || die "The cached UBports build tools are incomplete. Run ./scripts/build-ubuntu-touch.sh first."
fi

cd "$HALIUM_DIR"
source ./deviceinfo

DEVICE_TARBALL="$OUT_DIR/device_${deviceinfo_codename}_usrmerge.tar.xz"

build_ubuntu_touch_images() {
    local tarball="$1"
    [ -f "$tarball" ] || die "Device archive is missing: $tarball"

    printf '\n== Building Ubuntu Touch images ==\n'
    "$BUILD_TOOLS_DIR/prepare-fake-ota.sh" "$tarball" "$HALIUM_DIR/ota"
    "$BUILD_TOOLS_DIR/system-image-from-ota.sh" "$HALIUM_DIR/ota/ubuntu_command" "$HALIUM_DIR/images"
    printf '\nImages are in %s/images\n' "$HALIUM_DIR"
}

if [ "$TARGET" = images ]; then
    build_ubuntu_touch_images "$DEVICE_TARBALL"
    exit 0
fi

[ -f "$DEVICE_TARBALL" ] || die "Device archive is missing. Run ./scripts/build-ubuntu-touch.sh first."
mkdir -p "$WORK_DIR"
PARTIAL_DIR="$(mktemp -d "$WORK_DIR/partial-build.XXXXXX")"
trap 'rm -rf "$PARTIAL_DIR"' EXIT
mkdir -p "$PARTIAL_DIR/tmp"
ln -s "$DOWNLOADS_DIR" "$PARTIAL_DIR/downloads"

TMP_DIR="$PARTIAL_DIR/tmp"
mkdir -p "$TMP_DIR/partitions" "$TMP_DIR/system"

printf '\n== Preparing cached device archive ==\n'
tar -xJf "$DEVICE_TARBALL" -C "$TMP_DIR" partitions system

if [ "$TARGET" = boot ]; then
    printf '\n== Rebuilding boot.img from cached kernel objects ==\n'
    "$BUILD_TOOLS_DIR/build/make-bootimage.sh" \
        "$PARTIAL_DIR/downloads" \
        "$PARTIAL_DIR/downloads/KERNEL_OBJ" \
        "$PARTIAL_DIR/downloads/halium-boot-ramdisk.img" \
        "$TMP_DIR/partitions/boot.img" \
        "$TMP_DIR/system"

    printf '\n== Rebuilding boot-lz4.img and device archive ==\n'
    ./make-bootimages.sh -b "$PARTIAL_DIR" -o "$OUT_DIR"
    build_ubuntu_touch_images "$DEVICE_TARBALL"
    exit 0
fi

if [ "$TARGET" = overlay ]; then
    MODULES_DIR=""
    if [ -d "$TMP_DIR/system/usr/lib/modules" ]; then
        MODULES_DIR="$TMP_DIR/system/usr/lib/modules"
    elif [ -d "$TMP_DIR/system/lib/modules" ]; then
        MODULES_DIR="$TMP_DIR/system/lib/modules"
    fi

    if [ -n "$MODULES_DIR" ]; then
        mkdir -p "$PARTIAL_DIR/cached-modules"
        cp -a "$MODULES_DIR/." "$PARTIAL_DIR/cached-modules/"
    fi

    rm -rf "$TMP_DIR/system"
    mkdir -p "$TMP_DIR/system"
    if [ -n "$MODULES_DIR" ]; then
        mkdir -p "$TMP_DIR/system/usr/lib/modules"
        cp -a "$PARTIAL_DIR/cached-modules/." "$TMP_DIR/system/usr/lib/modules/"
    fi

    printf '\n== Rebuilding device archive from current system overlay ==\n'
    "$BUILD_TOOLS_DIR/build/build-tarball-mainline.sh" \
        "$deviceinfo_codename" "$OUT_DIR" "$TMP_DIR" usrmerge
    rm -f "$DEVICE_TARBALL"
    cp "$OUT_DIR/device_${deviceinfo_codename}.tar.xz" "$DEVICE_TARBALL"
    build_ubuntu_touch_images "$DEVICE_TARBALL"
    exit 0
fi

die "Internal error: unsupported target '$TARGET'."

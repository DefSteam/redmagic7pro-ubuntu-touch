#!/bin/bash
set -xe

BUILD_DIR=workdir
OUT=out

while [ $# -gt 0 ]
do
    case "$1" in
    (-b) BUILD_DIR="$2"; shift;;
    (-o) OUT="$2"; shift;;
    (-*) echo "$0: Error: unknown option $1" 1>&2; exit 1;;
    (*) OUT="$2"; break;;
    esac
    shift
done

BUILD_DIR="$(realpath "$BUILD_DIR")"
TMPDOWN="$BUILD_DIR/downloads"
OUT="$(realpath "$OUT")"
TMP="$BUILD_DIR/tmp"

source ./deviceinfo

deviceinfo_kernel_image_name="Image.lz4" ./build/make-bootimage.sh "$TMPDOWN" \
   "$TMPDOWN/KERNEL_OBJ" "$TMPDOWN/halium-boot-ramdisk.img" "$TMP/partitions/boot-lz4.img" "$TMP/system"

# Replace generated archives from earlier runs. The generic build may have left
# either name as a hard link or symlink, so remove both before writing them.
rm -f "$OUT/device_${deviceinfo_codename}_usrmerge.tar.xz" \
    "$OUT/device_${deviceinfo_codename}.tar.xz"
tar -cJf "$OUT/device_${deviceinfo_codename}_usrmerge.tar.xz" -C "$TMP" --owner=root --group=root partitions/ system/
# Keep both expected names as regular, independent archives so a later generic
# build cannot turn the usrmerge name into a self-referential symlink.
cp "$OUT/device_${deviceinfo_codename}_usrmerge.tar.xz" \
    "$OUT/device_${deviceinfo_codename}.tar.xz"

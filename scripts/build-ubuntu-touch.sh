#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HALIUM_DIR="$ROOT_DIR/halium-gki"
BUILD_TOOLS_DIR="$HALIUM_DIR/build"
BUILD_TOOLS_URL="https://gitlab.com/ubports/community-ports/halium-generic-adaptation-build-tools"
BUILD_TOOLS_REV="d5838d5c4cf90c7dbece749a451fb14271847dc9"
KERNEL_URL="https://github.com/DefSteam/nx709j-kernel.git"
KERNEL_REV="d0097b7cdb0a83a65f49a74ec04591ad6e3bc06c"

die() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

patch_is_applied() {
    local repo_dir="$1"
    local patch_file="$2"
    (cd "$repo_dir" && patch --dry-run --silent --reverse --batch -p1 < "$patch_file") \
        >/dev/null 2>&1
}

apply_patch_if_missing() {
    local repo_dir="$1"
    local patch_file="$2"
    if ! patch_is_applied "$repo_dir" "$patch_file"; then
        (cd "$repo_dir" && patch --dry-run --silent --batch -p1 < "$patch_file") || \
            die "Patch does not apply cleanly: $patch_file"
        (cd "$repo_dir" && patch --silent --batch -p1 < "$patch_file")
    fi
}

prepare_checkout() {
    local repo_dir="$1"
    local repo_url="$2"
    local revision="$3"
    shift 3
    local patch_file
    local current_revision
    local missing_patch=false
    local origin_url

    if [ -e "$repo_dir" ]; then
        git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || \
            die "$repo_dir exists but is not a Git checkout; move it aside and retry."
        origin_url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)"
        [ "$origin_url" = "$repo_url" ] || die "$repo_dir has an unexpected or missing origin URL."
    else
        mkdir -p "$repo_dir"
        git -C "$repo_dir" init -q
        git -C "$repo_dir" remote add origin "$repo_url"
    fi

    for patch_file in "$@"; do
        if ! patch_is_applied "$repo_dir" "$patch_file"; then
            missing_patch=true
        fi
    done

    if [ "$missing_patch" = true ]; then
        [ -z "$(git -C "$repo_dir" status --porcelain)" ] || \
            die "$repo_dir has local changes. Preserve them and use a clean checkout for this build."
    fi

    current_revision="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || true)"
    if [ "$current_revision" != "$revision" ]; then
        [ "$missing_patch" = true ] || die "$repo_dir is patched from an unexpected revision."
        git -C "$repo_dir" fetch --depth 1 origin "$revision"
        git -C "$repo_dir" checkout -q --detach FETCH_HEAD
        current_revision="$(git -C "$repo_dir" rev-parse HEAD)"
    fi
    [ "$current_revision" = "$revision" ] || die "Could not check out pinned revision $revision."

    for patch_file in "$@"; do
        apply_patch_if_missing "$repo_dir" "$patch_file"
    done
}

prepare_kernel() {
    local kernel_dir="$HALIUM_DIR/workdir/downloads/nx709j-kernel"
    local patch_file="$ROOT_DIR/patches/nx709j-kernel-kabi.patch"
    local current_revision
    local patch_applied=false
    local origin_url

    [ -d "$kernel_dir" ] || die "Kernel checkout is missing at $kernel_dir."
    origin_url="$(git -C "$kernel_dir" remote get-url origin 2>/dev/null || true)"
    [ "$origin_url" = "$KERNEL_URL" ] || die "Kernel checkout has an unexpected or missing origin URL."

    if patch_is_applied "$kernel_dir" "$patch_file"; then
        patch_applied=true
    fi
    if [ "$patch_applied" = false ]; then
        [ -z "$(git -C "$kernel_dir" status --porcelain)" ] || \
            die "Kernel checkout has local changes; refusing to overwrite them."
    fi

    current_revision="$(git -C "$kernel_dir" rev-parse HEAD)"
    if [ "$current_revision" != "$KERNEL_REV" ]; then
        [ "$patch_applied" = false ] || die "Kernel patch is applied to an unexpected revision."
        git -C "$kernel_dir" fetch --depth 1 origin "$KERNEL_REV"
        git -C "$kernel_dir" checkout -q --detach FETCH_HEAD
        current_revision="$(git -C "$kernel_dir" rev-parse HEAD)"
    fi
    [ "$current_revision" = "$KERNEL_REV" ] || die "Could not check out pinned kernel revision $KERNEL_REV."

    apply_patch_if_missing "$kernel_dir" "$patch_file"
}

cd "$HALIUM_DIR"
prepare_checkout "$BUILD_TOOLS_DIR" "$BUILD_TOOLS_URL" "$BUILD_TOOLS_REV" \
    "$ROOT_DIR/patches/build-tools.patch"

printf '\n== Downloading pinned build dependencies ==\n'
"$BUILD_TOOLS_DIR/build.sh" -c -b workdir -o out

prepare_kernel

printf '\n== Building kernel and device tarball ==\n'
"$BUILD_TOOLS_DIR/build.sh" -b workdir -o out
./make-bootimages.sh -b workdir -o out

printf '\n== Building Ubuntu Touch images ==\n'
"$BUILD_TOOLS_DIR/prepare-fake-ota.sh" \
    out/device_nx709j_usrmerge.tar.xz ota
"$BUILD_TOOLS_DIR/system-image-from-ota.sh" ota/ubuntu_command images
bash "$ROOT_DIR/scripts/validate-rootfs.sh" "$HALIUM_DIR/images/rootfs.img"

printf '\nBuild complete. Images are in %s/images\n' "$HALIUM_DIR"

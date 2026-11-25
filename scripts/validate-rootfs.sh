#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${1:-}"
if [ -z "$IMAGE" ] || [ ! -s "$IMAGE" ]; then
    printf 'ERROR: Root filesystem image is missing or empty: %s\n' "$IMAGE" >&2
    exit 1
fi

for tool in dumpe2fs debugfs; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'ERROR: %s is required to validate rootfs.img (install e2fsprogs).\n' "$tool" >&2
        exit 1
    }
done

if ! dumpe2fs -h "$IMAGE" >/dev/null 2>&1; then
    printf 'ERROR: %s is not a readable ext filesystem. Rebuild before installing.\n' "$IMAGE" >&2
    exit 1
fi

init_info="$(debugfs -R 'stat /init' "$IMAGE" 2>&1 || true)"
if ! grep -Eq '^Inode: [1-9][0-9]*' <<< "$init_info"; then
    printf 'ERROR: %s has no /init; rootfs image conversion did not finish. Rebuild before installing.\n' "$IMAGE" >&2
    exit 1
fi

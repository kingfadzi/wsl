#!/bin/bash
# F: drive mount helper
# Sources from: /usr/local/lib/mount-f-drive.sh
#
# Network drives don't automount in WSL. This helper attempts to mount F:
# If mount fails, /mnt/f still exists as a local directory (fallback).

# Mount point for F: drive
F_MOUNT="/mnt/f"

# Try to mount F: drive if not already mounted
try_mount_f_drive() {
    # Already mounted? Skip.
    if mountpoint -q "$F_MOUNT" 2>/dev/null; then
        return 0
    fi

    # Ensure mount point exists
    if [[ ! -d "$F_MOUNT" ]]; then
        sudo mkdir -p "$F_MOUNT" 2>/dev/null
    fi

    # Try to mount (network drive won't automount)
    if sudo mount -t drvfs F: "$F_MOUNT" 2>/dev/null; then
        return 0
    else
        echo "Warning: Failed to mount F: drive (network drive may be unavailable)" >&2
        return 1
    fi
}

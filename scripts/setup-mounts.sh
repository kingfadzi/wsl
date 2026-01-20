#!/bin/bash
# Setup Windows mounts (symlinks) on first login
# Sourced from /etc/profile.d/01-mounts.sh

# Only run for interactive shells
[[ $- != *i* ]] && return

# Source manifest for WIN_BASE_DIR
if [ -f /etc/wsl-manifest ]; then
    source /etc/wsl-manifest
fi
WIN_BASE_DIR="${WIN_BASE_DIR:-/mnt/c/devhome/projects/wsl}"

# Detect Windows username
WIN_USER=$(/mnt/c/Windows/System32/cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
if [ -z "$WIN_USER" ]; then
    return
fi

# Track if we created any new symlinks (for one-time message)
MOUNTS_CREATED=0

# Helper: create symlink if target exists and link doesn't
create_mount() {
    local link="$1"
    local target="$2"

    # Skip if link already exists (symlink or directory)
    [ -e "$link" ] || [ -L "$link" ] && return

    # Create symlink if target exists
    if [ -e "$target" ]; then
        ln -s "$target" "$link" 2>/dev/null && MOUNTS_CREATED=1
    fi
}

# Helper: create symlink with sudo (for system paths)
create_mount_sudo() {
    local link="$1"
    local target="$2"

    # Skip if link already exists
    [ -e "$link" ] || [ -L "$link" ] && return

    # Create symlink if target exists
    if [ -e "$target" ]; then
        sudo ln -sf "$target" "$link" 2>/dev/null && MOUNTS_CREATED=1
    fi
}

# Kerberos config (system-wide)
create_mount_sudo "/etc/krb5.conf" "${WIN_BASE_DIR}/krb5/krb5.conf"

# User home symlinks
create_mount "$HOME/.ssh" "${WIN_BASE_DIR}/ssh"
create_mount "$HOME/.claude" "${WIN_BASE_DIR}/claude"
create_mount "$HOME/Downloads" "/mnt/c/Users/${WIN_USER}/Downloads"
create_mount "$HOME/f" "/mnt/f"

# Fix SSH permissions (required for SSH to work)
if [ -L "$HOME/.ssh" ] && [ -d "$HOME/.ssh" ]; then
    chmod 700 "$HOME/.ssh" 2>/dev/null
    chmod 600 "$HOME/.ssh"/id_* 2>/dev/null
    chmod 644 "$HOME/.ssh"/*.pub 2>/dev/null
    chmod 644 "$HOME/.ssh/known_hosts" 2>/dev/null
    chmod 644 "$HOME/.ssh/config" 2>/dev/null
fi

# One-time message
if [ "$MOUNTS_CREATED" = "1" ]; then
    echo "Windows mounts configured. Run 'ls -la ~' to see symlinks."
fi

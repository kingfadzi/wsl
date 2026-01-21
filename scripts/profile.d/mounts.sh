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

# Helper: create symlink, creating target dir if missing
create_mount() {
    local link="$1"
    local target="$2"

    # Skip if already correct symlink
    [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ] && return

    # Create target dir if missing
    [ ! -e "$target" ] && mkdir -p "$target" 2>/dev/null

    # Create symlink (remove existing file first)
    if [ -e "$target" ]; then
        rm -f "$link" 2>/dev/null
        ln -s "$target" "$link" 2>/dev/null && MOUNTS_CREATED=1
    fi
}

# Helper: create symlink with sudo, creating target dir if missing
create_mount_sudo() {
    local link="$1"
    local target="$2"

    # Skip if already correct symlink
    [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ] && return

    # Create target dir if missing
    [ ! -e "$target" ] && sudo mkdir -p "$target" 2>/dev/null

    # Create symlink (remove existing file first)
    if [ -e "$target" ]; then
        sudo rm -f "$link" 2>/dev/null
        sudo ln -s "$target" "$link" 2>/dev/null && MOUNTS_CREATED=1
    fi
}

# Kerberos config (system-wide)
create_mount_sudo "/etc/krb5.conf" "${WIN_BASE_DIR}/krb5/krb5.conf"

# ODBC config (system-wide)
create_mount_sudo "/etc/odbc.ini" "${WIN_BASE_DIR}/odbc/odbc.ini"
create_mount_sudo "/etc/odbcinst.ini" "${WIN_BASE_DIR}/odbc/odbcinst.ini"

# Zscaler certificates directory (VPN only)
create_mount_sudo "/opt/wsl-certs/zscaler" "${WIN_BASE_DIR}/certs/zscaler"

# Secrets directory (API keys)
create_mount_sudo "/opt/wsl-secrets" "${WIN_BASE_DIR}/secrets"

# User home symlinks
create_mount "$HOME/.ssh" "${WIN_BASE_DIR}/ssh"
create_mount "$HOME/.claude" "${WIN_BASE_DIR}/claude"
create_mount "$HOME/Downloads" "/mnt/c/Users/${WIN_USER}/Downloads"
create_mount "$HOME/f" "/mnt/f"

# Package manager caches (avoid WSL bloat)
create_mount "$HOME/.m2" "${WIN_BASE_DIR}/m2"
create_mount "$HOME/.gradle" "${WIN_BASE_DIR}/gradle"
create_mount "$HOME/.npm" "${WIN_BASE_DIR}/npm"
create_mount "$HOME/.cache/pip" "${WIN_BASE_DIR}/pip-cache"

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

#!/bin/bash
# Download binary releases for WSL build
#
# Usage: ./download.sh [--force]
#   --force: Re-download even if files exist

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARIES_DIR="$SCRIPT_DIR/binaries"
CONFIG_FILE="$SCRIPT_DIR/profiles/base.args"

# === Binary URLs (add new binaries here) ===
AFFINE_URL="https://github.com/kingfadzi/AFFiNE/releases/download/v0.16.3/affine-0.16.3-linux-x64.tar.gz"
REDASH_URL="https://github.com/kingfadzi/redash-bundler/releases/download/v25.8.0/redash-bundle-v25.8.0.tgz"

# Parse arguments
FORCE=false
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=true ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

# Update config file with release filename
update_config() {
    local key="$1"
    local value="$2"

    if grep -q "^${key}=" "$CONFIG_FILE" 2>/dev/null; then
        # Update existing entry
        sed -i.bak "s|^${key}=.*|${key}=${value}|" "$CONFIG_FILE"
        rm -f "$CONFIG_FILE.bak"
    else
        # Append new entry
        echo "${key}=${value}" >> "$CONFIG_FILE"
    fi
}

# Download a binary
download_binary() {
    local name="$1"
    local url="$2"
    local release="$(echo "$name" | tr '[:upper:]' '[:lower:]').tar.gz"
    local dest="$BINARIES_DIR/$release"

    if [[ -f "$dest" ]] && [[ "$FORCE" != "true" ]]; then
        echo "Exists: $release (use --force to re-download)"
        return
    fi

    echo "Downloading: $name"
    echo "  URL: $url"
    echo "  Dest: $release"

    curl -fL# "$url" -o "$dest"

    # Update config
    update_config "${name}_RELEASE" "$release"
    echo "  Updated: ${name}_RELEASE=$release"

    echo "  Done: $(du -h "$dest" | cut -f1)"
}

# Ensure binaries directory exists
mkdir -p "$BINARIES_DIR"

echo "=== Downloading binaries ==="
echo

# Download each binary
download_binary "AFFINE" "$AFFINE_URL"
download_binary "REDASH" "$REDASH_URL"

echo
echo "=== Download complete ==="

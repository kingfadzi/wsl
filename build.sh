#!/bin/bash
#
# Build DevEnv WSL image
#
# Usage:
#   ./build.sh <profile> [distro-name]
#
# Profiles:
#   vpn - Public DNS (laptop/VPN)
#   lan - Corporate DNS (VDI/LAN)
#
# Examples:
#   ./build.sh vpn
#   ./build.sh vpn DevEnv
#   ./build.sh lan --no-cache
#   ./build.sh vpn --rebuild-base
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Base image configuration
WSL_BASE_REPO="${WSL_BASE_REPO:-git@github.com:kingfadzi/wsl-base.git}"
WSL_BASE_DIR="${WSL_BASE_DIR:-$HOME/.cache/wsl-base}"
# Check sibling directory first (for local development)
WSL_BASE_LOCAL="${SCRIPT_DIR}/../wsl-base"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}==>${NC} $1"; }
log_warn() { echo -e "${YELLOW}WARNING:${NC} $1"; }
log_error() { echo -e "${RED}ERROR:${NC} $1"; }

# Parse arguments
NO_CACHE=""
REBUILD_BASE=false
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --no-cache)
            NO_CACHE="--no-cache"
            ;;
        --rebuild-base)
            REBUILD_BASE=true
            ;;
        *)
            ARGS+=("$arg")
            ;;
    esac
done

PROFILE="${ARGS[0]:-vpn}"
DISTRO_NAME="${ARGS[1]:-DevEnv}"

if [[ ! -f "profiles/${PROFILE}.args" ]]; then
    log_error "Unknown profile '$PROFILE'"
    echo "Available profiles:"
    ls -1 profiles/*.args 2>/dev/null | xargs -n1 basename | sed 's/.args$//'
    exit 1
fi

IMAGE_NAME="wsl-${PROFILE}"
TARBALL="${IMAGE_NAME}.tar"

# ============================================
# Base Image Auto-Build
# ============================================
ensure_base_image() {
    local profile="$1"
    local base_image="wsl-base:$profile"

    # Check if we need to rebuild
    if [ "$REBUILD_BASE" = true ]; then
        log_info "Forcing rebuild of base image..."
    elif docker image inspect "$base_image" >/dev/null 2>&1; then
        log_info "Base image found: $base_image"
        return 0
    else
        log_warn "Base image not found: $base_image"
    fi

    # Determine where to build from
    local base_dir=""
    if [ -d "$WSL_BASE_LOCAL/.git" ]; then
        log_info "Using local wsl-base: $WSL_BASE_LOCAL"
        base_dir="$WSL_BASE_LOCAL"
    elif [ -d "$WSL_BASE_DIR/.git" ]; then
        log_info "Using cached wsl-base: $WSL_BASE_DIR"
        git -C "$WSL_BASE_DIR" pull --ff-only 2>/dev/null || true
        base_dir="$WSL_BASE_DIR"
    else
        log_info "Cloning wsl-base repository..."
        git clone --depth 1 "$WSL_BASE_REPO" "$WSL_BASE_DIR"
        base_dir="$WSL_BASE_DIR"
    fi

    # Build base image
    log_info "Building base image..."
    cd "$base_dir"
    ./binaries.sh 2>/dev/null || true
    ./build.sh "$profile" $NO_CACHE
    cd "$SCRIPT_DIR"
}

# Check binaries exist
check_binaries() {
    log_info "Checking binaries..."

    for bin in affine.tar.gz redash.tar.gz; do
        if [[ ! -f "$SCRIPT_DIR/binaries/$bin" ]]; then
            log_error "Missing binaries/$bin"
            echo "Download releases to the binaries/ directory"
            exit 1
        fi
    done

    echo "  All binaries present"
}

# Build Docker image
build_image() {
    echo ""
    echo "============================================"
    echo "  DevEnv WSL Builder"
    echo "============================================"
    echo "  Profile: $PROFILE"
    echo "  Image:   $IMAGE_NAME"
    echo "  Output:  $TARBALL"
    echo "============================================"
    echo ""

    # Build args from base + profile (use array to handle spaces in values)
    local BUILD_ARGS=("--build-arg" "PROFILE=$PROFILE")
    for args_file in "profiles/base.args" "profiles/${PROFILE}.args"; do
        [ -f "$args_file" ] || continue
        while IFS= read -r line; do
            line="${line%$'\r'}"  # Strip Windows carriage return
            # Skip comments and empty lines
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            BUILD_ARGS+=("--build-arg" "$line")
        done < "$args_file"
    done

    # Build
    log_info "Building image..."
    docker build $NO_CACHE -t "$IMAGE_NAME" "${BUILD_ARGS[@]}" .

    echo "  Built: $IMAGE_NAME"
}

# Export to tarball
export_image() {
    log_info "Exporting tarball..."
    local CONTAINER_ID
    CONTAINER_ID=$(docker create "$IMAGE_NAME")
    docker export "$CONTAINER_ID" -o "$TARBALL"
    docker rm "$CONTAINER_ID" > /dev/null

    local TARBALL_SIZE
    TARBALL_SIZE=$(du -h "$TARBALL" | cut -f1)
    echo "  Created: $TARBALL ($TARBALL_SIZE)"
}

# Prompt for WSL import (Windows only)
prompt_wsl_import() {
    # Check if running on Windows (Git Bash / MSYS)
    if [[ "$OSTYPE" != "msys" && "$OSTYPE" != "cygwin" && -z "$WINDIR" ]]; then
        echo ""
        echo "To import on Windows:"
        echo "  wsl --import $DISTRO_NAME C:\\WSL\\$DISTRO_NAME $TARBALL --version 2"
        return
    fi

    echo ""
    read -p "Import to WSL as '$DISTRO_NAME'? (y/N) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        local INSTALL_PATH="C:\\WSL\\$DISTRO_NAME"
        local TARBALL_WIN
        TARBALL_WIN=$(cygpath -w "$SCRIPT_DIR/$TARBALL")

        # Check if distro exists
        if wsl.exe --list --quiet 2>/dev/null | grep -q "^${DISTRO_NAME}$"; then
            echo "Distribution '$DISTRO_NAME' already exists."
            read -p "Unregister and replace? (y/N) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "Unregistering $DISTRO_NAME..."
                wsl.exe --unregister "$DISTRO_NAME"
            else
                echo "Aborted."
                return
            fi
        fi

        log_info "Importing to WSL..."
        echo "  Name: $DISTRO_NAME"
        echo "  Path: $INSTALL_PATH"

        # Create directory and import
        mkdir -p "$(cygpath "$INSTALL_PATH")" 2>/dev/null || true
        wsl.exe --import "$DISTRO_NAME" "$INSTALL_PATH" "$TARBALL_WIN" --version 2

        echo ""
        log_info "Import complete!"
        echo "To start: wsl -d $DISTRO_NAME"
    else
        echo ""
        echo "To import later:"
        echo "  wsl --import $DISTRO_NAME C:\\WSL\\$DISTRO_NAME $TARBALL --version 2"
    fi
}

# Main
main() {
    ensure_base_image "$PROFILE"
    check_binaries
    build_image
    export_image
    prompt_wsl_import

    echo ""
    log_info "Build complete!"
}

main

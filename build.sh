#!/bin/bash
# Build WSL image and export as tarball
# On Windows (Git Bash), optionally import to WSL
#
# Usage: ./build.sh <profile> [distro-name]
#   profile:     vpn (default) or lan
#   distro-name: WSL distribution name (default: DevEnv)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PROFILE="${1:-vpn}"
DISTRO_NAME="${2:-DevEnv}"

if [[ ! -f "profiles/${PROFILE}.args" ]]; then
    echo "Error: Unknown profile '$PROFILE'"
    echo "Available profiles:"
    ls -1 profiles/*.args 2>/dev/null | xargs -n1 basename | sed 's/.args$//'
    exit 1
fi

IMAGE_NAME="wsl-${PROFILE}"
TARBALL="${IMAGE_NAME}.tar"

echo "=== Building WSL image ==="
echo "Profile: $PROFILE"
echo "Image:   $IMAGE_NAME"
echo "Output:  $TARBALL"
echo

# Build args from base + profile (use array to handle spaces in values)
BUILD_ARGS=("--build-arg" "PROFILE=$PROFILE")
for args_file in "profiles/base.args" "profiles/${PROFILE}.args"; do
    while IFS= read -r line; do
        line="${line%$'\r'}"  # Strip Windows carriage return
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        BUILD_ARGS+=("--build-arg" "$line")
    done < "$args_file"
done

# Build
echo "Building image..."
docker build -t "$IMAGE_NAME" "${BUILD_ARGS[@]}" .

# Export
echo
echo "Exporting tarball..."
CONTAINER_ID=$(docker create "$IMAGE_NAME")
docker export "$CONTAINER_ID" -o "$TARBALL"
docker rm "$CONTAINER_ID" > /dev/null

TARBALL_SIZE=$(du -h "$TARBALL" | cut -f1)
echo
echo "=== Build complete ==="
echo "Created: $TARBALL ($TARBALL_SIZE)"

# Check if running on Windows (Git Bash / MSYS)
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || -n "$WINDIR" ]]; then
    echo
    read -p "Import to WSL as '$DISTRO_NAME'? (y/N) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        INSTALL_PATH="C:\\WSL\\$DISTRO_NAME"
        TARBALL_WIN=$(cygpath -w "$SCRIPT_DIR/$TARBALL")

        # Check if distro exists
        if wsl.exe --list --quiet 2>/dev/null | grep -q "^${DISTRO_NAME}$"; then
            echo "Distribution '$DISTRO_NAME' already exists."
            read -p "Unregister and replace? (y/N) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "Unregistering $DISTRO_NAME..."
                wsl.exe --unregister "$DISTRO_NAME"
            else
                echo "Aborted."
                exit 0
            fi
        fi

        echo "Importing to WSL..."
        echo "  Name: $DISTRO_NAME"
        echo "  Path: $INSTALL_PATH"

        # Create directory and import
        mkdir -p "$(cygpath "$INSTALL_PATH")" 2>/dev/null || true
        wsl.exe --import "$DISTRO_NAME" "$INSTALL_PATH" "$TARBALL_WIN" --version 2

        echo
        echo "=== Import complete ==="
        echo "To start: wsl -d $DISTRO_NAME"
    else
        echo
        echo "To import later:"
        echo "  wsl --import $DISTRO_NAME C:\\WSL\\$DISTRO_NAME $TARBALL --version 2"
    fi
else
    echo
    echo "To import on Windows:"
    echo "  wsl --import $DISTRO_NAME C:\\WSL\\$DISTRO_NAME $TARBALL --version 2"
fi

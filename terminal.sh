#!/bin/bash
# Configure Windows Terminal with settings from config/terminal.json
#
# Usage: ./terminal.sh [distro-name]
#   distro-name: Optional WSL distribution to configure

set -e

# Must run from Git Bash, not WSL
if [[ -n "$WSL_DISTRO_NAME" ]]; then
    echo "Error: Run this script from Git Bash, not WSL"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config/terminal.json"
SETTINGS_FILE="$LOCALAPPDATA/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed"
    echo "Install with: pacman -S jq (Git Bash) or scoop install jq"
    exit 1
fi

# Check config file
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
fi

# Check Windows Terminal settings
if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo "Error: Windows Terminal settings not found: $SETTINGS_FILE"
    exit 1
fi

DISTRO_NAME="${1:-}"

echo "=== Configuring Windows Terminal ==="
echo "Config: $CONFIG_FILE"
echo "Target: $SETTINGS_FILE"
[[ -n "$DISTRO_NAME" ]] && echo "Distro: $DISTRO_NAME"
echo

# Backup original settings on first run only
BACKUP_FILE="$SETTINGS_FILE.bak.original"
if [[ ! -f "$BACKUP_FILE" ]]; then
    cp "$SETTINGS_FILE" "$BACKUP_FILE"
    echo "Backed up original settings to $BACKUP_FILE"
fi

# Read configuration
COLOR_SCHEME=$(jq -r '.colorScheme' "$CONFIG_FILE")
FONT_FACE=$(jq -r '.font.face' "$CONFIG_FILE")
FONT_SIZE=$(jq -r '.font.size' "$CONFIG_FILE")
CURSOR_SHAPE=$(jq -r '.cursorShape' "$CONFIG_FILE")
PADDING=$(jq -r '.padding' "$CONFIG_FILE")
SCHEME_NAME=$(jq -r '.scheme.name' "$CONFIG_FILE")

# Read current settings
SETTINGS=$(cat "$SETTINGS_FILE")

# Check if color scheme already exists
SCHEME_EXISTS=$(echo "$SETTINGS" | jq --arg name "$SCHEME_NAME" '.schemes // [] | map(select(.name == $name)) | length')

if [[ "$SCHEME_EXISTS" == "0" ]]; then
    # Add color scheme from config
    SCHEME=$(jq '.scheme' "$CONFIG_FILE")
    SETTINGS=$(echo "$SETTINGS" | jq --argjson scheme "$SCHEME" '.schemes = ((.schemes // []) + [$scheme])')
    echo "Added color scheme: $SCHEME_NAME"
else
    echo "Color scheme already exists: $SCHEME_NAME"
fi

# Set profile defaults
SETTINGS=$(echo "$SETTINGS" | jq \
    --arg colorScheme "$COLOR_SCHEME" \
    --arg fontFace "$FONT_FACE" \
    --argjson fontSize "$FONT_SIZE" \
    --arg cursorShape "$CURSOR_SHAPE" \
    --arg padding "$PADDING" \
    '.profiles.defaults = (.profiles.defaults // {}) + {
        colorScheme: $colorScheme,
        font: { face: $fontFace, size: $fontSize },
        cursorShape: $cursorShape,
        padding: $padding
    }')
echo "Updated profile defaults"

# Configure specific WSL distro profile if provided
if [[ -n "$DISTRO_NAME" ]]; then
    # Find and update WSL profile by name or source
    SETTINGS=$(echo "$SETTINGS" | jq \
        --arg distro "$DISTRO_NAME" \
        --arg colorScheme "$COLOR_SCHEME" \
        --arg fontFace "$FONT_FACE" \
        --argjson fontSize "$FONT_SIZE" \
        '(.profiles.list[] | select(.name == $distro or .source == "Windows.Terminal.Wsl")) += {
            colorScheme: $colorScheme,
            font: { face: $fontFace, size: $fontSize }
        }')
    echo "Updated WSL profile: $DISTRO_NAME"
fi

# Save settings
echo "$SETTINGS" | jq '.' > "$SETTINGS_FILE"

echo
echo "=== Configuration complete ==="
echo "Restart Windows Terminal to apply changes"

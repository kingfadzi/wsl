#!/bin/bash
# Load API keys from Windows mount
# Sourced from /etc/profile.d/04-secrets.sh

[[ $- != *i* ]] && return

SECRETS_FILE="/opt/wsl-secrets/api-keys.env"

if [ -f "$SECRETS_FILE" ]; then
    set -a
    source "$SECRETS_FILE"
    set +a
fi

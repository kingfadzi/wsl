#!/bin/bash
# Source NVM for all shells
# Sourced from /etc/profile.d/05-nvm.sh

# Load NVM config from manifest
if [ -f /etc/wsl-manifest ]; then
    source /etc/wsl-manifest
fi

export NVM_DIR="${NVM_DIR:-/opt/nvm}"
export NVM_CURL_OPTIONS="-#"
export NODE_EXTRA_CA_CERTS="/etc/pki/tls/certs/ca-bundle.crt"
[ -n "$NVM_NODEJS_ORG_MIRROR" ] && export NVM_NODEJS_ORG_MIRROR

# Source NVM (adds node/npm/yarn/claude-code to PATH)
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# Bash completion only for interactive shells
if [[ $- == *i* ]]; then
    [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
fi

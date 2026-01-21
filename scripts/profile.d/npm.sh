#!/bin/bash
# Configure npm/yarn registry at runtime
# Sourced from /etc/profile.d/06-npm.sh

[[ $- != *i* ]] && return

# Load config from manifest
if [ -f /etc/wsl-manifest ]; then
    source /etc/wsl-manifest
fi

# Export npm config via environment variables (takes precedence over .npmrc)
if [ -n "$NPM_REGISTRY" ]; then
    export NPM_CONFIG_REGISTRY="$NPM_REGISTRY"
fi
export NPM_CONFIG_CAFILE="/etc/pki/tls/certs/ca-bundle.crt"

# Export sass binary site for node-sass
if [ -n "$SASS_BINARY_SITE" ]; then
    export SASS_BINARY_SITE
fi

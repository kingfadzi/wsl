#!/bin/bash
# Start AFFiNE server with the custom ESM loader
# The loader enables extensionless imports in the compiled dist/ code

export NVM_DIR=/opt/nvm
if [ -s "$NVM_DIR/nvm.sh" ]; then
    source "$NVM_DIR/nvm.sh"
else
    echo "ERROR: NVM not found at $NVM_DIR/nvm.sh"
    exit 1
fi

if ! command -v node &>/dev/null; then
    echo "ERROR: node not found after sourcing NVM"
    exit 1
fi

cd /opt/affine
exec node --import ./scripts/register.js ./dist/index.js

#!/bin/bash
# Start AFFiNE server with the custom ESM loader
# The loader enables extensionless imports in the compiled dist/ code

# Source NVM to get node in PATH (systemd doesn't source profile.d)
source /opt/nvm/nvm.sh

cd /opt/affine
exec node --import ./scripts/register.js ./dist/index.js

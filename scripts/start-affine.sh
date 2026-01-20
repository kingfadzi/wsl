#!/bin/bash
# Start AFFiNE server with the custom ESM loader
# The loader enables extensionless imports in the compiled dist/ code
cd /opt/affine
exec node --import ./scripts/register.js ./dist/index.js

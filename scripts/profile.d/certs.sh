#!/bin/bash
# Add Zscaler certs to system trust (VPN only)
# Sourced from /etc/profile.d/02-certs.sh

[[ $- != *i* ]] && return

ZSCALER_CERT_DIR="/opt/wsl-certs/zscaler"
CERT_DEST="/etc/pki/ca-trust/source/anchors"
MARKER="/var/lib/wsl-zscaler-updated"

[ ! -d "$ZSCALER_CERT_DIR" ] && return

# Check if certs changed
if [ -f "$MARKER" ]; then
    [ "$(stat -c %Y "$ZSCALER_CERT_DIR" 2>/dev/null)" = "$(stat -c %Y "$MARKER" 2>/dev/null)" ] && return
fi

# Copy/convert Zscaler certs
for cert in "$ZSCALER_CERT_DIR"/*.{pem,crt,cer} 2>/dev/null; do
    [ -f "$cert" ] || continue
    name=$(basename "$cert" | sed 's/\.[^.]*$//')
    case "$cert" in
        *.cer) sudo openssl x509 -inform DER -in "$cert" -out "$CERT_DEST/${name}.pem" 2>/dev/null || \
               sudo cp "$cert" "$CERT_DEST/${name}.pem" ;;
        *)     sudo cp "$cert" "$CERT_DEST/" ;;
    esac
done

sudo update-ca-trust extract 2>/dev/null
sudo touch -r "$ZSCALER_CERT_DIR" "$MARKER" 2>/dev/null
echo "Zscaler certificates updated."

#!/bin/bash
# Update system certificates from Windows mount
# Sourced from /etc/profile.d/02-certs.sh

# Only run for interactive shells
[[ $- != *i* ]] && return

CERT_SOURCE="/opt/wsl-certs/ca"
CERT_DEST="/etc/pki/ca-trust/source/anchors"
CERT_MARKER="/var/lib/wsl-certs-updated"
JAVA_CACERTS_SOURCE="/opt/wsl-certs/java/cacerts"

# Skip if no certs directory mounted
[ ! -d "$CERT_SOURCE" ] && return

# Check if certs have changed (compare directory mtime)
if [ -f "$CERT_MARKER" ]; then
    SOURCE_MTIME=$(stat -c %Y "$CERT_SOURCE" 2>/dev/null)
    MARKER_MTIME=$(stat -c %Y "$CERT_MARKER" 2>/dev/null)
    [ "$SOURCE_MTIME" = "$MARKER_MTIME" ] && return
fi

# Copy PEM/CRT certs directly to system trust store
CERTS_COPIED=0
for cert in "$CERT_SOURCE"/*.pem "$CERT_SOURCE"/*.crt; do
    [ -f "$cert" ] || continue
    sudo cp "$cert" "$CERT_DEST/" 2>/dev/null && CERTS_COPIED=1
done

# Convert DER certs (.cer) to PEM format individually
for cert in "$CERT_SOURCE"/*.cer; do
    [ -f "$cert" ] || continue
    name=$(basename "$cert" .cer)
    # Try DER format first, fall back to PEM
    sudo sh -c "openssl x509 -inform DER -in '$cert' > '$CERT_DEST/${name}.pem' 2>/dev/null || openssl x509 -in '$cert' > '$CERT_DEST/${name}.pem'"
    CERTS_COPIED=1
done

# Update system trust if certs were copied
if [ "$CERTS_COPIED" = "1" ]; then
    sudo update-ca-trust extract 2>/dev/null
    echo "System certificates updated from Windows mount."
fi

# Update Java cacerts if provided
if [ -f "$JAVA_CACERTS_SOURCE" ]; then
    JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java) 2>/dev/null)) 2>/dev/null)
    if [ -n "$JAVA_HOME" ] && [ -d "$JAVA_HOME/lib/security" ]; then
        sudo cp "$JAVA_CACERTS_SOURCE" "$JAVA_HOME/lib/security/cacerts" 2>/dev/null
        echo "Java cacerts updated from Windows mount."
    fi
fi

# Update marker timestamp to match source
sudo touch -r "$CERT_SOURCE" "$CERT_MARKER" 2>/dev/null

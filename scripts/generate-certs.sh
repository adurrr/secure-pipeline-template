#!/usr/bin/env bash
set -euo pipefail

CERT_DIR="$(cd "$(dirname "$0")/.." && pwd)/docker/certs"

mkdir -p "$CERT_DIR"

if [ -f "$CERT_DIR/server.crt" ]; then
    echo "Certificates already exist in $CERT_DIR — skipping."
    echo "Delete them and re-run this script to regenerate."
    exit 0
fi

echo "Generating self-signed TLS certificate for local development..."

openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout "$CERT_DIR/server.key" \
    -out "$CERT_DIR/server.crt" \
    -subj "/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

chmod 600 "$CERT_DIR/server.key"
chmod 644 "$CERT_DIR/server.crt"

echo "Done. Certificates written to $CERT_DIR"

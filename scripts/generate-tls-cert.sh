#!/bin/bash
# =============================================================================
# IceMailArchive - TLS-Zertifikat fuer Proton Bridge Wrapper
# =============================================================================
# Erstellt eine lokale CA + signiertes Server-Zertifikat fuer den socat
# TLS-Wrapper, der Proton Bridge STARTTLS in implizites SSL umwandelt.
#
# OpenArchiver unterstuetzt kein STARTTLS, daher wird socat als Proxy
# dazwischengeschaltet:
#   Client (OA) --SSL--> socat:11143 --STARTTLS--> Bridge:1143
#
# Erzeugte Dateien:
#   /etc/ssl/private/proton-bridge-ca.crt   (CA-Zertifikat)
#   /etc/ssl/private/proton-bridge-ca.key   (CA-Schluessel)
#   /etc/ssl/private/proton-tls.crt         (Server-Zertifikat)
#   /etc/ssl/private/proton-tls.key         (Server-Schluessel)
#
# Das CA-Zertifikat wird nach ./proton-tls.crt kopiert (fuer Docker Mount).
# =============================================================================

set -euo pipefail

CERT_DIR="/etc/ssl/private"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CA_DAYS=3650
CERT_DAYS=3650

echo "=== Proton Bridge TLS-Zertifikat Generator ==="
echo ""

mkdir -p "$CERT_DIR"

# --- CA erstellen ---
if [ ! -f "$CERT_DIR/proton-bridge-ca.key" ]; then
    echo "[1/3] Erstelle lokale CA..."
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$CERT_DIR/proton-bridge-ca.key" \
        -out "$CERT_DIR/proton-bridge-ca.crt" \
        -days $CA_DAYS \
        -subj "/CN=Local Bridge CA"
else
    echo "[1/3] CA existiert bereits"
fi

# --- Server-Zertifikat erstellen ---
echo "[2/3] Erstelle Server-Zertifikat (SAN: 127.0.0.1, localhost)..."

# CSR erstellen
openssl req -newkey rsa:2048 -nodes \
    -keyout "$CERT_DIR/proton-tls.key" \
    -out "$CERT_DIR/proton-tls.csr" \
    -subj "/CN=Proton Bridge TLS Wrapper"

# Mit CA signieren (inkl. SAN)
openssl x509 -req \
    -in "$CERT_DIR/proton-tls.csr" \
    -CA "$CERT_DIR/proton-bridge-ca.crt" \
    -CAkey "$CERT_DIR/proton-bridge-ca.key" \
    -CAcreateserial \
    -out "$CERT_DIR/proton-tls.crt" \
    -days $CERT_DAYS \
    -extfile <(printf "subjectAltName=IP:127.0.0.1,DNS:localhost")

# Aufraeumen
rm -f "$CERT_DIR/proton-tls.csr" "$CERT_DIR/proton-bridge-ca.srl"

# --- CA-Cert ins Projekt kopieren (fuer Docker Mount) ---
echo "[3/3] Kopiere CA-Zertifikat ins Projekt..."
cp "$CERT_DIR/proton-bridge-ca.crt" "$PROJECT_DIR/proton-tls.crt"

# Berechtigungen
chmod 600 "$CERT_DIR/proton-tls.key" "$CERT_DIR/proton-bridge-ca.key"
chmod 644 "$CERT_DIR/proton-tls.crt" "$CERT_DIR/proton-bridge-ca.crt"
chmod 644 "$PROJECT_DIR/proton-tls.crt"

echo ""
echo "=== Fertig ==="
echo ""
echo "  CA-Zertifikat:     $CERT_DIR/proton-bridge-ca.crt"
echo "  Server-Zertifikat: $CERT_DIR/proton-tls.crt"
echo "  Server-Schluessel: $CERT_DIR/proton-tls.key"
echo "  Docker-Mount:      $PROJECT_DIR/proton-tls.crt"
echo ""
echo "  Gueltig fuer: $CERT_DAYS Tage"
echo ""
echo "  Systemd-Service (proton-tls-wrapper) verwendet:"
echo "    cert=$CERT_DIR/proton-tls.crt"
echo "    key=$CERT_DIR/proton-tls.key"

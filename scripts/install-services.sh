#!/bin/bash
# =============================================================================
# IceMailArchive - Systemd-Services installieren
# =============================================================================
# Installiert und aktiviert:
#   - maildrop-watcher.service  (Datei-Import ueber Samba-Share)
#   - proton-tls-wrapper.service (TLS-Proxy fuer Proton Bridge)
#
# Ausfuehren:  sudo ./scripts/install-services.sh [--maildrop] [--proton] [--all]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

install_maildrop() {
    echo "[+] Installiere Maildrop-Watcher..."

    # Script kopieren
    cp "$PROJECT_DIR/scripts/maildrop-watcher.sh" /usr/local/bin/
    chmod +x /usr/local/bin/maildrop-watcher.sh

    # Verzeichnisse anlegen
    mkdir -p /srv/maildrop/.failed

    # Systemd-Service
    cp "$PROJECT_DIR/systemd/maildrop-watcher.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now maildrop-watcher.service

    echo "[+] Maildrop-Watcher installiert und gestartet"
    echo "    Status: systemctl status maildrop-watcher"
    echo "    Logs:   journalctl -u maildrop-watcher -f"
}

install_proton_tls() {
    echo "[+] Installiere Proton TLS-Wrapper..."

    # socat pruefen
    if ! command -v socat &>/dev/null; then
        echo "[!] socat nicht gefunden - installiere..."
        apt-get update -qq && apt-get install -y -qq socat
    fi

    # Zertifikate generieren falls noetig
    if [ ! -f /etc/ssl/private/proton-tls.crt ]; then
        echo "[+] Generiere TLS-Zertifikate..."
        bash "$PROJECT_DIR/scripts/generate-tls-cert.sh"
    fi

    # Systemd-Service
    cp "$PROJECT_DIR/systemd/proton-tls-wrapper.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now proton-tls-wrapper.service

    echo "[+] Proton TLS-Wrapper installiert und gestartet"
    echo "    Port: 11143 (SSL) -> 1143 (STARTTLS)"
    echo "    Status: systemctl status proton-tls-wrapper"
}

install_samba() {
    echo "[+] Konfiguriere Samba-Share..."

    if ! command -v smbd &>/dev/null; then
        echo "[!] Samba nicht gefunden - installiere..."
        apt-get update -qq && apt-get install -y -qq samba
    fi

    if ! grep -q "\[maildrop\]" /etc/samba/smb.conf 2>/dev/null; then
        cat "$PROJECT_DIR/samba/maildrop.conf" >> /etc/samba/smb.conf
        systemctl restart smbd
        echo "[+] Samba-Share [maildrop] hinzugefuegt"
    else
        echo "[!] Samba-Share [maildrop] existiert bereits"
    fi
}

# =============================================================================

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Bitte als root ausfuehren: sudo $0"
    exit 1
fi

case "${1:-}" in
    --maildrop)
        install_samba
        install_maildrop
        ;;
    --proton)
        install_proton_tls
        ;;
    --all)
        install_samba
        install_maildrop
        install_proton_tls
        ;;
    *)
        echo "Verwendung: $0 [--maildrop|--proton|--all]"
        echo ""
        echo "  --maildrop  Maildrop-Watcher + Samba-Share installieren"
        echo "  --proton    Proton Bridge TLS-Wrapper installieren"
        echo "  --all       Alles installieren"
        exit 1
        ;;
esac

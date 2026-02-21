#!/bin/bash
# =============================================================================
# IceMailArchive - Automatisches Setup
# =============================================================================
# Richtet die komplette Email-Archivierung ein:
#   1. Abhaengigkeiten pruefen (Docker, socat, samba)
#   2. .env aus Template erstellen (mit generierten Geheimnissen)
#   3. Verzeichnisse anlegen
#   4. Docker-Stack starten
#   5. Optional: Maildrop-Watcher + Samba installieren
#   6. Optional: Proton Bridge TLS-Wrapper installieren
#
# Ausfuehren:
#   chmod +x scripts/setup.sh
#   sudo ./scripts/setup.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
ENV_EXAMPLE="$PROJECT_DIR/.env.example"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }
ask()  { echo -e "${CYAN}[?]${NC} $*"; }

# =============================================================================
# Voraussetzungen pruefen
# =============================================================================

check_prerequisites() {
    log "Pruefe Voraussetzungen..."

    local missing=()

    if ! command -v docker &>/dev/null; then
        missing+=("docker")
    fi
    if ! docker compose version &>/dev/null 2>&1; then
        missing+=("docker-compose-plugin")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        err "Fehlende Abhaengigkeiten: ${missing[*]}"
        echo "  Installation: https://docs.docker.com/engine/install/"
        exit 1
    fi

    log "Docker $(docker --version | grep -oP '\d+\.\d+\.\d+') gefunden"
}

# =============================================================================
# .env erstellen
# =============================================================================

generate_env() {
    if [ -f "$ENV_FILE" ]; then
        warn ".env existiert bereits - ueberspringe"
        return
    fi

    log "Erstelle .env mit generierten Geheimnissen..."

    # Server-IP ermitteln
    local server_ip
    server_ip=$(hostname -I | awk '{print $1}')
    ask "Server-IP fuer OpenArchiver [$server_ip]: "
    read -r input_ip
    [ -n "$input_ip" ] && server_ip="$input_ip"

    # Speicherpfad
    local storage_path="/data/openarchiver/storage"
    ask "Speicherpfad fuer Emails [$storage_path]: "
    read -r input_path
    [ -n "$input_path" ] && storage_path="$input_path"

    # Geheimnisse generieren
    local pg_pass meili_key redis_pass enc_key storage_enc jwt_secret
    pg_pass=$(openssl rand -base64 24)
    meili_key=$(openssl rand -hex 16)
    redis_pass=$(openssl rand -base64 16)
    enc_key=$(openssl rand -hex 32)
    storage_enc=$(openssl rand -hex 32)
    jwt_secret=$(openssl rand -hex 32)

    # .env aus Template erstellen
    cp "$ENV_EXAMPLE" "$ENV_FILE"

    # Werte ersetzen
    sed -i "s|YOUR_SERVER_IP|${server_ip}|g" "$ENV_FILE"
    sed -i "s|CHANGE_ME_postgres_password|${pg_pass}|g" "$ENV_FILE"
    sed -i "s|CHANGE_ME_meilisearch_key|${meili_key}|g" "$ENV_FILE"
    sed -i "s|CHANGE_ME_redis_password|${redis_pass}|g" "$ENV_FILE"
    sed -i "s|CHANGE_ME_64_hex_chars_storage_encryption|${storage_enc}|g" "$ENV_FILE"
    sed -i "s|CHANGE_ME_64_hex_chars_encryption|${enc_key}|g" "$ENV_FILE"
    sed -i "s|CHANGE_ME_64_hex_chars_jwt|${jwt_secret}|g" "$ENV_FILE"
    sed -i "s|/data/openarchiver/storage|${storage_path}|g" "$ENV_FILE"

    chmod 600 "$ENV_FILE"
    log ".env erstellt (chmod 600)"
}

# =============================================================================
# Verzeichnisse anlegen
# =============================================================================

create_directories() {
    log "Erstelle Verzeichnisse..."

    # Speicherpfad aus .env lesen
    local storage_path
    storage_path=$(grep '^STORAGE_HOST_PATH=' "$ENV_FILE" | cut -d= -f2)

    mkdir -p "$storage_path"
    mkdir -p /srv/maildrop/.failed
    mkdir -p /var/log

    log "Verzeichnisse erstellt"
}

# =============================================================================
# Docker-Stack starten
# =============================================================================

start_stack() {
    log "Starte Docker-Stack..."
    cd "$PROJECT_DIR"
    docker compose up -d

    log "Warte auf Healthchecks..."
    local retries=30
    while [ $retries -gt 0 ]; do
        if docker compose ps postgres | grep -q "healthy"; then
            break
        fi
        sleep 2
        retries=$((retries - 1))
    done

    if [ $retries -eq 0 ]; then
        warn "PostgreSQL Healthcheck Timeout - pruefe 'docker compose logs postgres'"
    else
        log "Alle Services gestartet"
    fi

    docker compose ps
}

# =============================================================================
# Maildrop + Samba installieren
# =============================================================================

install_maildrop() {
    ask "Maildrop-Watcher + Samba-Share installieren? (j/N): "
    read -r answer
    [[ ! "$answer" =~ ^[jJyY] ]] && return

    # Samba installieren falls noetig
    if ! command -v smbd &>/dev/null; then
        log "Installiere Samba..."
        apt-get update -qq && apt-get install -y -qq samba
    fi

    # Samba-Konfiguration
    if ! grep -q "\[maildrop\]" /etc/samba/smb.conf 2>/dev/null; then
        log "Fuege Samba-Share [maildrop] hinzu..."
        cat "$PROJECT_DIR/samba/maildrop.conf" >> /etc/samba/smb.conf
        systemctl restart smbd
        log "Samba-Share [maildrop] konfiguriert"
    else
        warn "Samba-Share [maildrop] existiert bereits"
    fi

    # Maildrop-Watcher installieren
    log "Installiere Maildrop-Watcher..."
    cp "$PROJECT_DIR/scripts/maildrop-watcher.sh" /usr/local/bin/
    chmod +x /usr/local/bin/maildrop-watcher.sh

    # .env-Werte im Watcher anpassen
    local app_url
    app_url=$(grep '^APP_URL=' "$ENV_FILE" | cut -d= -f2 | tr -d '"')
    local backend_port
    backend_port=$(grep '^PORT_BACKEND=' "$ENV_FILE" | cut -d= -f2)
    # Backend laeuft auf localhost
    sed -i "s|OA_BACKEND=.*|OA_BACKEND=\"http://localhost:${backend_port:-4000}\"|" \
        /usr/local/bin/maildrop-watcher.sh

    cp "$PROJECT_DIR/systemd/maildrop-watcher.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now maildrop-watcher.service

    log "Maildrop-Watcher installiert und gestartet"
    log "Samba-Share: \\\\$(hostname -I | awk '{print $1}')\\maildrop"
}

# =============================================================================
# Proton Bridge TLS-Wrapper installieren
# =============================================================================

install_proton_tls() {
    ask "Proton Bridge TLS-Wrapper installieren? (j/N): "
    read -r answer
    [[ ! "$answer" =~ ^[jJyY] ]] && return

    # socat pruefen
    if ! command -v socat &>/dev/null; then
        log "Installiere socat..."
        apt-get update -qq && apt-get install -y -qq socat
    fi

    # TLS-Zertifikat generieren
    log "Generiere TLS-Zertifikat..."
    bash "$PROJECT_DIR/scripts/generate-tls-cert.sh"

    # Systemd-Service installieren
    cp "$PROJECT_DIR/systemd/proton-tls-wrapper.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now proton-tls-wrapper.service

    log "TLS-Wrapper auf Port 11143 gestartet"
    log "OpenArchiver IMAP-Einstellungen fuer Proton:"
    echo "  Host: 127.0.0.1"
    echo "  Port: 11143"
    echo "  SSL:  true"
}

# =============================================================================
# Zusammenfassung
# =============================================================================

print_summary() {
    local server_ip
    server_ip=$(grep '^APP_URL=' "$ENV_FILE" | grep -oP '\d+\.\d+\.\d+\.\d+')

    echo ""
    echo "============================================================"
    echo " IceMailArchive - Setup abgeschlossen!"
    echo "============================================================"
    echo ""
    echo "  Web-UI:    http://${server_ip}:3000"
    echo "  API:       http://localhost:4000"
    echo ""
    echo "  Naechste Schritte:"
    echo "    1. http://${server_ip}:3000 oeffnen"
    echo "    2. Admin-Account erstellen"
    echo "    3. Ingestion Sources > New > IMAP-Konten hinzufuegen"
    echo ""

    if systemctl is-active --quiet maildrop-watcher 2>/dev/null; then
        echo "  Maildrop:  \\\\${server_ip}\\maildrop"
        echo "             ZIP/PST/MBOX-Dateien per Drag&Drop importieren"
        echo ""
    fi

    echo "  Dokumentation: https://icepaule.github.io/IceMailArchive/"
    echo "============================================================"
}

# =============================================================================
# Hauptprogramm
# =============================================================================

echo "============================================================"
echo " IceMailArchive - Setup"
echo " Email-Archivierung mit OpenArchiver"
echo "============================================================"
echo ""

# Root-Check
if [ "$EUID" -ne 0 ]; then
    err "Bitte als root ausfuehren: sudo $0"
    exit 1
fi

check_prerequisites
generate_env
create_directories
start_stack
install_maildrop
install_proton_tls
print_summary

#!/bin/bash
# =============================================================================
# IceMailArchive - Maildrop Watcher
# =============================================================================
# Ueberwacht /srv/maildrop/ auf neue Dateien und importiert sie automatisch
# in OpenArchiver.
#
# Unterstuetzte Formate:
#   .zip  -> EML Import (ZIP mit .eml Dateien, Ordnerstruktur bleibt erhalten)
#   .pst  -> PST Import (Outlook Archivdateien)
#   .mbox -> MBOX Import (Standard Unix Mailbox Format)
#
# Nach erfolgreichem Import wird die Quelldatei geloescht.
# Fehlgeschlagene Dateien werden nach /srv/maildrop/.failed/ verschoben.
#
# Installation:
#   sudo cp scripts/maildrop-watcher.sh /usr/local/bin/
#   sudo chmod +x /usr/local/bin/maildrop-watcher.sh
#   sudo cp systemd/maildrop-watcher.service /etc/systemd/system/
#   sudo systemctl enable --now maildrop-watcher
# =============================================================================

set -euo pipefail

DROPDIR="/srv/maildrop"
FAILDIR="${DROPDIR}/.failed"
LOGFILE="/var/log/maildrop-watcher.log"
LOCKDIR="/tmp/maildrop-watcher.lock"

# OpenArchiver Backend - anpassen falls anderer Port/Host
OA_BACKEND="http://localhost:4000"
# OpenArchiver Zugangsdaten (Admin-Account)
OA_EMAIL="${OA_EMAIL:-admin@example.com}"
OA_PASSWORD="${OA_PASSWORD:-changeme}"

# Scan-Intervall in Sekunden
SCAN_INTERVAL=10
# Warten bis Datei fertig geschrieben (Sekunden ohne Groessenaenderung)
STABLE_WAIT=3

mkdir -p "$FAILDIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

get_token() {
    local response
    response=$(curl -s -X POST "${OA_BACKEND}/v1/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"${OA_EMAIL}\",\"password\":\"${OA_PASSWORD}\"}" 2>/dev/null)

    echo "$response" | python3 -c \
        "import sys,json; print(json.load(sys.stdin).get('accessToken',''))" 2>/dev/null
}

upload_file() {
    local filepath="$1"
    local token="$2"

    local response
    response=$(curl -s -X POST "${OA_BACKEND}/v1/upload" \
        -H "authorization: Bearer ${token}" \
        -F "file=@${filepath}" 2>/dev/null)

    echo "$response" | python3 -c \
        "import sys,json; print(json.load(sys.stdin).get('filePath',''))" 2>/dev/null
}

create_ingestion_source() {
    local name="$1"
    local provider="$2"
    local uploaded_path="$3"
    local token="$4"

    local body
    body=$(python3 -c "
import json
print(json.dumps({
    'name': '$name',
    'provider': '$provider',
    'providerConfig': {
        'uploadedFilePath': '$uploaded_path'
    }
}))
")

    local response
    response=$(curl -s -X POST "${OA_BACKEND}/v1/ingestion-sources" \
        -H "authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "$body" 2>/dev/null)

    local status
    status=$(echo "$response" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d.get('status','error'))" 2>/dev/null)

    if [ "$status" = "auth_success" ] || [ "$status" = "pending_auth" ] || [ "$status" = "syncing" ]; then
        local src_id
        src_id=$(echo "$response" | python3 -c \
            "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
        echo "$src_id"
    else
        log "  ERROR: API-Antwort: $response"
        echo ""
    fi
}

wait_for_stable() {
    local filepath="$1"
    local prev_size=-1
    local stable_count=0

    while [ $stable_count -lt $STABLE_WAIT ]; do
        if [ ! -f "$filepath" ]; then
            return 1
        fi
        local curr_size
        curr_size=$(stat -c%s "$filepath" 2>/dev/null || echo 0)
        if [ "$curr_size" = "$prev_size" ] && [ "$curr_size" -gt 0 ]; then
            stable_count=$((stable_count + 1))
        else
            stable_count=0
        fi
        prev_size=$curr_size
        sleep 1
    done
    return 0
}

detect_provider() {
    local filename="$1"
    local ext="${filename##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

    case "$ext" in
        zip) echo "eml_import" ;;
        pst) echo "pst_import" ;;
        mbox|mbx) echo "mbox_import" ;;
        *) echo "" ;;
    esac
}

process_file() {
    local filepath="$1"
    local filename
    filename=$(basename "$filepath")

    local provider
    provider=$(detect_provider "$filename")

    if [ -z "$provider" ]; then
        log "  SKIP: Unbekanntes Format: $filename (nur .zip/.pst/.mbox)"
        return
    fi

    log "  Verarbeite: $filename (Provider: $provider)"

    # Warten bis Datei fertig geschrieben ist
    if ! wait_for_stable "$filepath"; then
        log "  SKIP: Datei verschwunden: $filename"
        return
    fi

    local filesize
    filesize=$(du -h "$filepath" | cut -f1)
    log "  Groesse: $filesize"

    # Token holen
    local token
    token=$(get_token)
    if [ -z "$token" ]; then
        log "  ERROR: OpenArchiver Login fehlgeschlagen"
        mv "$filepath" "$FAILDIR/"
        return
    fi

    # Datei hochladen
    log "  Uploading..."
    local uploaded_path
    uploaded_path=$(upload_file "$filepath" "$token")
    if [ -z "$uploaded_path" ]; then
        log "  ERROR: Upload fehlgeschlagen"
        mv "$filepath" "$FAILDIR/"
        return
    fi
    log "  Uploaded: $uploaded_path"

    # Import-Quelle erstellen
    local import_name="Maildrop: ${filename} ($(date '+%Y-%m-%d %H:%M'))"
    log "  Erstelle Import: $import_name"
    local source_id
    source_id=$(create_ingestion_source "$import_name" "$provider" "$uploaded_path" "$token")

    if [ -n "$source_id" ]; then
        log "  OK: Import erstellt (ID: $source_id)"
        log "  Loesche Quelldatei: $filepath"
        rm -f "$filepath"
    else
        log "  ERROR: Import-Erstellung fehlgeschlagen"
        mv "$filepath" "$FAILDIR/"
    fi
}

# =============================================================================
# Main Loop
# =============================================================================

# Lock gegen mehrfache Instanzen
if ! mkdir "$LOCKDIR" 2>/dev/null; then
    echo "Bereits gestartet (Lock: $LOCKDIR)" >&2
    exit 1
fi
trap 'rmdir "$LOCKDIR" 2>/dev/null' EXIT

log "=== Maildrop Watcher gestartet ==="
log "Drop-Point: $DROPDIR"
log "Formate: .zip (EML), .pst, .mbox"
log "Scan-Intervall: ${SCAN_INTERVAL}s"

while true; do
    while IFS= read -r -d '' filepath; do
        log "Neue Datei erkannt: $(basename "$filepath")"
        process_file "$filepath"
    done < <(find "$DROPDIR" -maxdepth 1 -type f \
        \( -iname "*.zip" -o -iname "*.pst" -o -iname "*.mbox" -o -iname "*.mbx" \) \
        -print0 2>/dev/null)

    sleep "$SCAN_INTERVAL"
done

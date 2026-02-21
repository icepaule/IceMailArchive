#!/bin/bash
# =============================================================================
# IceMailArchive - Email-Speicher zu NFS migrieren
# =============================================================================
# Migriert den lokalen Email-Speicher auf ein NFS-Share (z.B. Synology NAS).
#
# Voraussetzungen:
#   - NFS-Export auf dem NAS konfiguriert
#   - nfs-common installiert (apt install nfs-common)
#
# Was dieses Script macht:
#   1. Stoppt den OpenArchiver Stack
#   2. Rsync lokale Daten zum NFS-Mount
#   3. Benennt lokales Verzeichnis um, mountet NFS am selben Pfad
#   4. Startet Stack neu (keine Docker-Aenderungen noetig!)
#
# Ausfuehren:
#   sudo ./scripts/migrate-to-nfs.sh NAS_IP:/pfad/zum/export
# =============================================================================

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Bitte als root ausfuehren: sudo $0"
    exit 1
fi

if [ $# -lt 1 ]; then
    echo "Verwendung: $0 NFS_SOURCE"
    echo ""
    echo "  NFS_SOURCE: NFS-Export (z.B. 10.10.33.20:/volume2/NAS/openarchiver)"
    echo ""
    echo "Beispiel:"
    echo "  sudo $0 10.10.33.20:/volume2/NAS/openarchiver"
    exit 1
fi

NFS_SOURCE="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Speicherpfad aus .env lesen
if [ -f "$PROJECT_DIR/.env" ]; then
    STORAGE_DIR=$(grep '^STORAGE_HOST_PATH=' "$PROJECT_DIR/.env" | cut -d= -f2)
fi
STORAGE_DIR="${STORAGE_DIR:-/data/openarchiver/storage}"
BACKUP_DIR="${STORAGE_DIR}.local-backup"

echo "=== IceMailArchive NFS Migration ==="
echo ""
echo "  Quell-Verzeichnis: ${STORAGE_DIR}"
echo "  NFS-Export:        ${NFS_SOURCE}"
echo "  Backup:            ${BACKUP_DIR}"
echo ""
read -p "Fortfahren? (j/N) " -n 1 -r
echo
[[ ! $REPLY =~ ^[jJyY]$ ]] && exit 1

# Schritt 1: Stack stoppen
echo "[1/5] Stoppe OpenArchiver..."
cd "$PROJECT_DIR"
docker compose down

# Schritt 2: fstab-Eintrag
if ! grep -q "$NFS_SOURCE" /etc/fstab; then
    echo "[2/5] Fuege NFS-Mount zu /etc/fstab hinzu..."
    mkdir -p /mnt/nfs-openarchiver
    echo "${NFS_SOURCE}  /mnt/nfs-openarchiver  nfs  rw,hard,intr,nfsvers=3,rsize=32768,wsize=32768  0  0" >> /etc/fstab
else
    echo "[2/5] fstab-Eintrag existiert bereits"
fi

# Schritt 3: Daten synchronisieren
echo "[3/5] Mounte NFS und synchronisiere Daten..."
mount /mnt/nfs-openarchiver
rsync -avP --delete "${STORAGE_DIR}/" /mnt/nfs-openarchiver/
umount /mnt/nfs-openarchiver

# Schritt 4: Swap local -> NFS
echo "[4/5] Ersetze lokalen Speicher durch NFS-Mount..."
mv "${STORAGE_DIR}" "${BACKUP_DIR}"
mkdir -p "${STORAGE_DIR}"
sed -i "s|/mnt/nfs-openarchiver|${STORAGE_DIR}|" /etc/fstab
mount "${STORAGE_DIR}"

# Schritt 5: Neustart
echo "[5/5] Starte OpenArchiver..."
cd "$PROJECT_DIR"
docker compose up -d

echo ""
echo "=== Migration abgeschlossen! ==="
echo ""
echo "  Lokales Backup: ${BACKUP_DIR} (nach Pruefung loeschbar)"
echo "  NFS gemountet:  ${STORAGE_DIR}"
echo ""
echo "  Pruefen: df -h ${STORAGE_DIR}"
echo "  Pruefen: docker compose ps"

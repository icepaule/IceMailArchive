---
layout: default
title: NFS-Migration
---

# NFS-Migration

[Zurueck zur Startseite](./)

---

## Uebersicht

Der Email-Speicher kann von der lokalen Festplatte auf ein NFS-Share (z.B. Synology NAS, TrueNAS) migriert werden, ohne die Docker-Konfiguration zu aendern.

<p align="center">
  <img src="images/nfs-migration.svg" alt="NFS-Migration: Vorher (lokal) und Nachher (NAS)" width="720">
</p>

---

## Voraussetzungen

- NFS-Export auf dem NAS konfiguriert
- `nfs-common` auf dem Server installiert
- Ausreichend Speicher auf dem NAS

```bash
sudo apt install nfs-common
```

---

## Automatische Migration

```bash
sudo ./scripts/migrate-to-nfs.sh NAS_IP:/pfad/zum/export
```

Beispiel:
```bash
sudo ./scripts/migrate-to-nfs.sh 10.10.33.20:/volume2/NAS/openarchiver
```

Das Skript:
1. Stoppt den OpenArchiver Stack
2. Mountet den NFS-Export temporaer
3. Synchronisiert alle Daten per rsync
4. Benennt das lokale Verzeichnis um (Backup)
5. Mountet NFS am gleichen Pfad
6. Aktualisiert `/etc/fstab`
7. Startet den Stack neu

---

## Manuelle Migration

### Schritt 1: NFS-Export erstellen

**Synology DSM:**
1. Systemsteuerung > Freigegebener Ordner > Neuer Ordner
2. NFS-Berechtigungen: Server-IP mit read/write
3. NFS-Version: v3 oder v4

**TrueNAS:**
1. Sharing > NFS > Add
2. Pfad und erlaubte Hosts konfigurieren

### Schritt 2: Stack stoppen

```bash
cd IceMailArchive
docker compose down
```

### Schritt 3: Daten synchronisieren

```bash
# NFS temporaer mounten
sudo mkdir -p /mnt/nfs-temp
sudo mount -t nfs NAS_IP:/pfad/zum/export /mnt/nfs-temp

# Daten kopieren
sudo rsync -avP /data/openarchiver/storage/ /mnt/nfs-temp/

# Verifizieren
diff <(du -s /data/openarchiver/storage/) <(du -s /mnt/nfs-temp/)

sudo umount /mnt/nfs-temp
```

### Schritt 4: Mount einrichten

```bash
# Lokales Verzeichnis umbenennen (Backup)
sudo mv /data/openarchiver/storage /data/openarchiver/storage.local-backup

# Neues Verzeichnis erstellen
sudo mkdir -p /data/openarchiver/storage

# fstab-Eintrag
echo "NAS_IP:/pfad/zum/export  /data/openarchiver/storage  nfs  rw,hard,intr,nfsvers=3,rsize=32768,wsize=32768  0  0" \
  | sudo tee -a /etc/fstab

# Mounten
sudo mount /data/openarchiver/storage
```

### Schritt 5: Stack starten

```bash
docker compose up -d
```

### Schritt 6: Pruefen

```bash
# Mount pruefen
df -h /data/openarchiver/storage

# Stack pruefen
docker compose ps

# Emails in der UI pruefen
# http://SERVER:3000
```

---

## Zurueck zur lokalen Speicherung

```bash
docker compose down
sudo umount /data/openarchiver/storage
sudo rmdir /data/openarchiver/storage
sudo mv /data/openarchiver/storage.local-backup /data/openarchiver/storage
# fstab-Eintrag entfernen
docker compose up -d
```

---

[Zurueck zur Startseite](./) | [Weiter: Troubleshooting](troubleshooting)

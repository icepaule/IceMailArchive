---
layout: default
title: Installation
---

# Installation

[Zurueck zur Startseite](./)

---

## Voraussetzungen

| Komponente | Minimum | Empfohlen |
|-----------|---------|-----------|
| **OS** | Debian 12 / Ubuntu 22.04+ | Debian 13 / Ubuntu 24.04 |
| **Docker** | 24.0+ mit Compose Plugin | 27.0+ |
| **RAM** | 4 GB | 8 GB+ |
| **Speicher** | 20 GB (System) | 50+ GB (je nach Mailvolumen) |
| **CPU** | 2 Kerne | 4+ Kerne |

### Software-Abhaengigkeiten

```bash
# Docker (falls nicht installiert)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Optionale Pakete (fuer Proton Bridge + Maildrop)
sudo apt install socat samba
```

---

## Automatische Installation

Das Setup-Skript fuehrt alle Schritte automatisch aus:

```bash
git clone https://github.com/icepaule/IceMailArchive.git
cd IceMailArchive
sudo ./scripts/setup.sh
```

Das Skript fragt interaktiv:
1. **Server-IP** - Wird automatisch erkannt, kann ueberschrieben werden
2. **Speicherpfad** - Standard: `/data/openarchiver/storage`
3. **Maildrop installieren?** - Samba-Share + Watcher-Service
4. **Proton TLS installieren?** - TLS-Wrapper fuer Proton Bridge

---

## Manuelle Installation

### Schritt 1: Repository klonen

```bash
git clone https://github.com/icepaule/IceMailArchive.git
cd IceMailArchive
```

### Schritt 2: Konfiguration erstellen

```bash
cp .env.example .env
```

Geheimnisse generieren und in `.env` eintragen:

```bash
# PostgreSQL Passwort
openssl rand -base64 24

# Meilisearch Key
openssl rand -hex 16

# Redis/Valkey Passwort
openssl rand -base64 16

# Encryption Keys (2x)
openssl rand -hex 32

# JWT Secret
openssl rand -hex 32
```

Die `.env`-Datei anpassen - mindestens diese Werte aendern:

```bash
APP_URL=http://DEINE_IP:3000
ORIGIN=http://DEINE_IP:3000
POSTGRES_PASSWORD=<generierter-wert>
DATABASE_URL="postgresql://archiver:<generierter-wert>@127.0.0.1:5432/open_archive"
MEILI_MASTER_KEY=<generierter-wert>
REDIS_PASSWORD=<generierter-wert>
STORAGE_ENCRYPTION_KEY=<generierter-wert>
ENCRYPTION_KEY=<generierter-wert>
JWT_SECRET=<generierter-wert>
```

Siehe [Konfiguration](configuration) fuer alle Optionen.

### Schritt 3: Speicherverzeichnis anlegen

```bash
sudo mkdir -p /data/openarchiver/storage
```

### Schritt 4: Docker-Stack starten

```bash
docker compose up -d
```

Pruefen ob alles laeuft:

```bash
docker compose ps
```

Erwartete Ausgabe:

```
NAME             STATUS          PORTS
oa-meilisearch   Up              127.0.0.1:7700->7700/tcp
oa-postgres      Up (healthy)    127.0.0.1:5432->5432/tcp
oa-tika          Up              127.0.0.1:9998->9998/tcp
oa-valkey        Up              127.0.0.1:6379->6379/tcp
open-archiver    Up              (host network)
```

### Schritt 5: Admin-Account erstellen

1. Browser oeffnen: `http://DEINE_IP:3000`
2. "Sign Up" klicken
3. Admin-Account mit Email + Passwort erstellen
4. Anmelden

### Schritt 6: IMAP-Quellen einrichten

In der Web-UI:
1. **Ingestion Sources** im Menue
2. **New Source** klicken
3. **Generic IMAP** waehlen
4. IMAP-Daten eintragen (Host, Port, Username, Passwort)
5. Speichern - der Sync startet automatisch

---

## Optionale Komponenten

### Maildrop (Samba-Share)

```bash
sudo ./scripts/install-services.sh --maildrop
```

Details: [Maildrop-Dokumentation](maildrop)

### Proton Bridge

```bash
# 1. Proton Bridge starten
docker compose -f docker-compose.proton.yml up -d

# 2. TLS-Wrapper installieren
sudo ./scripts/install-services.sh --proton
```

Details: [Proton Bridge Dokumentation](proton-bridge)

### Alles auf einmal

```bash
sudo ./scripts/install-services.sh --all
```

---

## Update

```bash
cd IceMailArchive

# Neue Images ziehen
docker compose pull

# Stack neustarten
docker compose down && docker compose up -d

# Optional: Proton Bridge updaten
docker compose -f docker-compose.proton.yml pull
docker compose -f docker-compose.proton.yml down
docker compose -f docker-compose.proton.yml up -d
```

---

## Deinstallation

```bash
# Stack stoppen und Volumes BEHALTEN
docker compose down

# Stack stoppen und Volumes LOESCHEN (ACHTUNG: Daten gehen verloren!)
docker compose down -v

# Systemd-Services entfernen
sudo systemctl disable --now maildrop-watcher proton-tls-wrapper
sudo rm /etc/systemd/system/maildrop-watcher.service
sudo rm /etc/systemd/system/proton-tls-wrapper.service
sudo systemctl daemon-reload
```

---

[Zurueck zur Startseite](./) | [Weiter: Konfiguration](configuration)

---
layout: default
title: Maildrop
---

# Maildrop - Datei-Import per Samba-Share

[Zurueck zur Startseite](./)

---

## Uebersicht

Der Maildrop ist ein Samba/SMB-Share, in den Email-Archive per Drag&Drop abgelegt werden koennen. Ein Hintergrund-Daemon (`maildrop-watcher`) ueberwacht das Verzeichnis und importiert neue Dateien automatisch in OpenArchiver.

```
┌──────────────┐     SMB/CIFS      ┌──────────────┐
│ Windows PC   │ ──────────────────>│ /srv/maildrop│
│ macOS        │  \\SERVER\maildrop │              │
│ Linux        │                    │  .zip  ✓     │
└──────────────┘                    │  .pst  ✓     │
                                    │  .mbox ✓     │
                                    └──────┬───────┘
                                           │
                                    Scan alle 10s
                                           │
                                    ┌──────▼───────┐
                                    │ maildrop-    │
                                    │ watcher.sh   │
                                    │              │
                                    │ 1. Upload    │
                                    │ 2. Import    │
                                    │ 3. Loeschen  │
                                    └──────┬───────┘
                                           │
                                    REST API (:4000)
                                           │
                                    ┌──────▼───────┐
                                    │ OpenArchiver │
                                    └──────────────┘
```

---

## Unterstuetzte Formate

| Format | Endung | Beschreibung |
|--------|--------|-------------|
| **EML (ZIP)** | `.zip` | ZIP-Archiv mit `.eml` Dateien - Ordnerstruktur bleibt erhalten |
| **PST** | `.pst` | Microsoft Outlook Archivdateien |
| **MBOX** | `.mbox`, `.mbx` | Standard Unix Mailbox Format (Thunderbird, etc.) |

---

## Installation

### Schnell (alles auf einmal)

```bash
sudo ./scripts/install-services.sh --maildrop
```

### Manuell

#### 1. Samba installieren

```bash
sudo apt install samba
```

#### 2. Share konfigurieren

```bash
# Verzeichnisse anlegen
sudo mkdir -p /srv/maildrop/.failed

# Samba-Konfiguration anfuegen
sudo cat samba/maildrop.conf >> /etc/samba/smb.conf

# Samba neustarten
sudo systemctl restart smbd
```

#### 3. Watcher installieren

```bash
# Script kopieren
sudo cp scripts/maildrop-watcher.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/maildrop-watcher.sh

# Systemd-Service installieren
sudo cp systemd/maildrop-watcher.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now maildrop-watcher
```

#### 4. Zugangsdaten konfigurieren

Der Watcher benoetigt OpenArchiver-Zugangsdaten. Diese koennen als Environment-Variablen im Systemd-Service oder direkt im Script gesetzt werden:

```bash
sudo systemctl edit maildrop-watcher
```

```ini
[Service]
Environment=OA_EMAIL=admin@example.com
Environment=OA_PASSWORD=your_password
```

```bash
sudo systemctl restart maildrop-watcher
```

---

## Verwendung

### Von Windows

1. Windows-Explorer oeffnen
2. In Adressleiste eingeben: `\\SERVER_IP\maildrop`
3. ZIP/PST/MBOX-Datei hineinziehen
4. Warten (10-30 Sekunden) - Datei verschwindet nach Import

### Von macOS

1. Finder > Gehe zu > Mit Server verbinden
2. `smb://SERVER_IP/maildrop`
3. Dateien in den Ordner kopieren

### Von Linux

```bash
# Einmalig mounten
sudo mount -t cifs //SERVER_IP/maildrop /mnt/maildrop -o guest

# Datei kopieren
cp archiv.zip /mnt/maildrop/
```

---

## Workflow

1. **Datei erkennen** - Watcher scannt `/srv/maildrop/` alle 10 Sekunden
2. **Stable-Check** - Wartet 3 Sekunden ohne Groessenaenderung (Datei fertig geschrieben?)
3. **API-Login** - Holt JWT-Token vom OpenArchiver Backend
4. **Upload** - Datei wird per `POST /v1/upload` hochgeladen
5. **Import erstellen** - `POST /v1/ingestion-sources` mit dem Provider-Typ
6. **Aufraeuumen** - Quelldatei wird geloescht (bei Fehler nach `.failed/` verschoben)

---

## Logs und Status

```bash
# Systemd-Status
sudo systemctl status maildrop-watcher

# Live-Logs
sudo journalctl -u maildrop-watcher -f

# Log-Datei
tail -f /var/log/maildrop-watcher.log
```

### Fehlgeschlagene Imports

Dateien die nicht importiert werden konnten, liegen in `/srv/maildrop/.failed/`:

```bash
ls -la /srv/maildrop/.failed/
```

---

## Mailstore Home Export

So exportierst du Emails aus Mailstore Home als ZIP mit EML-Dateien:

1. Mailstore Home oeffnen
2. Archiv-Ordner rechtsklick > **Export**
3. Format: **EML-Dateien**
4. Ziel: Beliebiger Ordner
5. Die erzeugten EML-Dateien in ein ZIP packen
6. ZIP in den Maildrop-Share legen

---

## Samba-Sicherheit

Der Maildrop-Share ist standardmaessig als **Guest-Share** (ohne Authentifizierung) konfiguriert. Das ist fuer ein lokales Netzwerk ok, aber:

- **Nicht im Internet exponieren!**
- Fuer mehr Sicherheit: Guest-Zugriff deaktivieren und Samba-User anlegen:

```bash
# Guest deaktivieren
sudo sed -i 's/guest ok = yes/guest ok = no/' /etc/samba/smb.conf
sudo sed -i 's/public = yes/public = no/' /etc/samba/smb.conf

# Samba-User anlegen
sudo smbpasswd -a archiver
sudo systemctl restart smbd
```

---

[Zurueck zur Startseite](./) | [Weiter: Windows-Import](windows-import)

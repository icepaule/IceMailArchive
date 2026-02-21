# IceMailArchive

**Self-hosted Email-Archivierung** mit [OpenArchiver](https://github.com/logiclabshq/open-archiver) - alle Emails sicher, durchsuchbar und AES-256-verschluesselt archivieren.

---

## Architektur

<p align="center">
  <img src="docs/images/architecture-overview.svg" alt="IceMailArchive Architektur-Uebersicht" width="800">
</p>

---

## Features

| Feature | Beschreibung |
|---------|-------------|
| **Multi-Account IMAP** | Gmail, iCloud, Outlook.com, GMX, Web.de, Posteo, Mailbox.org, u.v.m. |
| **ProtonMail** | Ueber Proton Bridge + TLS-Wrapper automatisch archivieren |
| **Maildrop (SMB)** | ZIP/PST/MBOX per Drag&Drop ueber Samba-Freigabe importieren |
| **Windows-Import** | PowerShell liest Outlook-Konten aus und importiert direkt per API |
| **Volltextsuche** | Meilisearch durchsucht Emails + Anhaenge (via Apache Tika OCR) |
| **AES-256** | Gespeicherte Emails sind verschluesselt |
| **NFS-faehig** | Speicher auf NAS migrierbar (Synology, TrueNAS) |
| **Docker** | Ein `docker compose up -d` startet alles |

---

## Schnellstart

```bash
# Klonen
git clone https://github.com/icepaule/IceMailArchive.git
cd IceMailArchive

# Setup (interaktiv: IP, Passwoerter werden generiert)
sudo ./scripts/setup.sh

# Browser: http://YOUR_IP:3000
```

---

## Komponenten

| Service | Image | Port | Funktion |
|---------|-------|------|----------|
| OpenArchiver | `logiclabshq/open-archiver:latest` | 3000, 4000 | Frontend + Backend |
| PostgreSQL 17 | `postgres:17-alpine` | 5432 | Metadaten + Accounts |
| Valkey 8 | `valkey/valkey:8-alpine` | 6379 | Job-Queue + Cache |
| Meilisearch | `getmeili/meilisearch:v1.15` | 7700 | Volltextsuche |
| Apache Tika | `apache/tika:3.2.2.0-full` | 9998 | Anhang-Textextraktion |
| Proton Bridge | `shenxn/protonmail-bridge:latest` | 1143 | ProtonMail IMAP (opt.) |

---

## Projektstruktur

```
IceMailArchive/
├── docker-compose.yml              # Haupt-Stack
├── docker-compose.proton.yml       # Proton Bridge (optional)
├── .env.example                    # Konfigurations-Template
├── scripts/
│   ├── setup.sh                    # Automatisches Setup
│   ├── maildrop-watcher.sh         # Datei-Import Daemon
│   ├── generate-tls-cert.sh        # TLS-Cert fuer Proton Wrapper
│   ├── install-services.sh         # Systemd-Services installieren
│   └── migrate-to-nfs.sh           # Speicher auf NFS migrieren
├── systemd/
│   ├── maildrop-watcher.service    # Systemd: Datei-Import
│   └── proton-tls-wrapper.service  # Systemd: TLS-Proxy
├── samba/
│   └── maildrop.conf               # Samba-Share Konfiguration
├── windows/
│   ├── Export-OutlookToOpenArchiver.ps1  # Outlook -> OpenArchiver
│   └── Export-OutlookCredentials.ps1     # Outlook Credentials Export
└── docs/                           # GitHub Pages Dokumentation
```

---

## Dokumentation

Die vollstaendige Dokumentation ist als GitHub Pages verfuegbar:

**[icepaule.github.io/IceMailArchive](https://icepaule.github.io/IceMailArchive/)**

| Seite | Inhalt |
|-------|--------|
| [Installation](https://icepaule.github.io/IceMailArchive/installation) | Setup-Anleitung Schritt fuer Schritt |
| [Konfiguration](https://icepaule.github.io/IceMailArchive/configuration) | .env-Datei, IMAP-Provider, Sync-Frequenz |
| [Architektur](https://icepaule.github.io/IceMailArchive/architecture) | Technische Details, Datenfluss, Verschluesselung |
| [Proton Bridge](https://icepaule.github.io/IceMailArchive/proton-bridge) | ProtonMail + TLS-Wrapper einrichten |
| [Maildrop](https://icepaule.github.io/IceMailArchive/maildrop) | Samba-Share fuer ZIP/PST/MBOX Import |
| [Windows-Import](https://icepaule.github.io/IceMailArchive/windows-import) | PowerShell-Skripte fuer Outlook |
| [NFS-Migration](https://icepaule.github.io/IceMailArchive/nfs-migration) | Speicher auf NAS verlagern |
| [Troubleshooting](https://icepaule.github.io/IceMailArchive/troubleshooting) | Haeufige Probleme + Loesungen |

---

## IMAP-Provider

Getestet und dokumentiert:

| Provider | Server | App-Password |
|----------|--------|-------------|
| Gmail | imap.gmail.com:993 | [Erstellen](https://myaccount.google.com/apppasswords) |
| iCloud | imap.mail.me.com:993 | [Erstellen](https://appleid.apple.com) |
| Outlook.com | outlook.office365.com:993 | [Erstellen](https://account.live.com/proofs/AppPassword) |
| ProtonMail | 127.0.0.1:11143 (via Bridge) | Bridge-Passwort |
| GMX | imap.gmx.net:993 | Normales PW |
| Web.de | imap.web.de:993 | Normales PW |
| T-Online | secureimap.t-online.de:993 | App-Password |
| Posteo | posteo.de:993 | Normales PW |
| Mailbox.org | imap.mailbox.org:993 | Normales PW |

---

## Voraussetzungen

- Linux (Debian 12+ / Ubuntu 22.04+)
- Docker 24.0+ mit Compose Plugin
- 4 GB RAM (8 GB empfohlen)
- Optional: Samba, socat (fuer Maildrop / Proton Bridge)

---

## Lizenz

MIT

---

*Erstellt mit [Claude Code](https://claude.com/claude-code) (Anthropic) auf einem Intel NUC mit Home Assistant.*

---
layout: default
title: Konfiguration
---

# Konfiguration

[Zurueck zur Startseite](./)

---

## .env-Datei

Die gesamte Konfiguration erfolgt ueber die `.env`-Datei. Vorlage: `.env.example`.

### Anwendung

| Variable | Standard | Beschreibung |
|----------|----------|-------------|
| `NODE_ENV` | `production` | Umgebung (production/development) |
| `PORT_BACKEND` | `4000` | Backend API Port |
| `PORT_FRONTEND` | `3000` | Frontend Web-UI Port |
| `APP_URL` | - | Oeffentliche URL (z.B. `http://192.168.1.100:3000`) |
| `ORIGIN` | - | CORS Origin (gleich wie APP_URL) |
| `SYNC_FREQUENCY` | `*/5 * * * *` | Sync-Intervall (Cron-Syntax) |
| `ALL_INCLUSIVE_ARCHIVE` | `false` | Junk/Trash-Ordner mitarchivieren |

### Datenbank (PostgreSQL)

| Variable | Standard | Beschreibung |
|----------|----------|-------------|
| `POSTGRES_DB` | `open_archive` | Datenbankname |
| `POSTGRES_USER` | `archiver` | Datenbankbenutzer |
| `POSTGRES_PASSWORD` | - | **Pflicht:** Datenbankpasswort |
| `DATABASE_URL` | - | **Pflicht:** Vollstaendige Connection-URL |

### Suche (Meilisearch)

| Variable | Standard | Beschreibung |
|----------|----------|-------------|
| `MEILI_MASTER_KEY` | - | **Pflicht:** API-Schluessel |
| `MEILI_HOST` | `http://127.0.0.1:7700` | Meilisearch URL |
| `MEILI_INDEXING_BATCH` | `500` | Batch-Groesse fuer Indexierung |

### Cache (Valkey/Redis)

| Variable | Standard | Beschreibung |
|----------|----------|-------------|
| `REDIS_HOST` | `127.0.0.1` | Valkey Host |
| `REDIS_PORT` | `6379` | Valkey Port |
| `REDIS_PASSWORD` | - | **Pflicht:** Valkey-Passwort |
| `REDIS_TLS_ENABLED` | `false` | TLS fuer Valkey |

### Speicher

| Variable | Standard | Beschreibung |
|----------|----------|-------------|
| `STORAGE_TYPE` | `local` | Speichertyp |
| `STORAGE_LOCAL_ROOT_PATH` | `/var/data/open-archiver` | Pfad im Container |
| `STORAGE_HOST_PATH` | `/data/openarchiver/storage` | Pfad auf dem Host |
| `BODY_SIZE_LIMIT` | `Infinity` | Max. Upload-Groesse |

### Verschluesselung

| Variable | Beschreibung |
|----------|-------------|
| `STORAGE_ENCRYPTION_KEY` | **Pflicht:** AES-256 Key fuer Email-Verschluesselung (64 Hex-Zeichen) |
| `ENCRYPTION_KEY` | **Pflicht:** Master-Key fuer IMAP-Credentials (64 Hex-Zeichen) |

**Wichtig:** Diese Keys generieren und sicher aufbewahren! Ohne den `STORAGE_ENCRYPTION_KEY` koennen archivierte Emails nicht entschluesselt werden.

```bash
# Key generieren (64 Hex-Zeichen = 256 Bit)
openssl rand -hex 32
```

### Sicherheit

| Variable | Standard | Beschreibung |
|----------|----------|-------------|
| `JWT_SECRET` | - | **Pflicht:** JWT-Signaturschluessel |
| `JWT_EXPIRES_IN` | `7d` | Token-Gueltigkeit |
| `RATE_LIMIT_WINDOW_MS` | `60000` | Rate-Limit Fenster (ms) |
| `RATE_LIMIT_MAX_REQUESTS` | `100` | Max. Requests pro Fenster |
| `ENABLE_DELETION` | `true` | Email-Loeschung erlauben |

### Node.js

| Variable | Beschreibung |
|----------|-------------|
| `NODE_OPTIONS` | `--dns-result-order=ipv4first` - IPv4 bevorzugen |
| `NODE_TLS_REJECT_UNAUTHORIZED` | `0` - Selbstsignierte Zertifikate erlauben (fuer Proton TLS-Wrapper) |

### Apache Tika

| Variable | Standard | Beschreibung |
|----------|----------|-------------|
| `TIKA_URL` | `http://127.0.0.1:9998` | Tika-Server URL |

---

## IMAP-Provider Einstellungen

### Ueberblick

| Provider | IMAP Server | Port | SSL | App-Password |
|----------|-------------|------|-----|-------------|
| **Gmail** | imap.gmail.com | 993 | Ja | [Erstellen](https://myaccount.google.com/apppasswords) |
| **iCloud** | imap.mail.me.com | 993 | Ja | [Erstellen](https://appleid.apple.com) |
| **Outlook.com** | outlook.office365.com | 993 | Ja | [Erstellen](https://account.live.com/proofs/AppPassword) |
| **GMX** | imap.gmx.net | 993 | Ja | Normales PW (IMAP aktivieren!) |
| **Web.de** | imap.web.de | 993 | Ja | Normales PW (IMAP aktivieren!) |
| **T-Online** | secureimap.t-online.de | 993 | Ja | App-Password im Kundencenter |
| **Posteo** | posteo.de | 993 | Ja | Normales Passwort |
| **Mailbox.org** | imap.mailbox.org | 993 | Ja | Normales Passwort |
| **ProtonMail** | 127.0.0.1 | 11143 | Ja | Bridge-Passwort (siehe [Proton Bridge](proton-bridge)) |
| **Yahoo** | imap.mail.yahoo.com | 993 | Ja | App-Password |
| **Eigener Server** | imap.example.com | 993 | Ja | Normales Passwort |

### IPv6-Probleme

Falls der Server kein IPv6-Routing hat (z.B. hinter einem IPv4-only Router), kann Gmail IMAP fehlschlagen. Loesung:

**Option A:** In `docker-compose.yml` unter `extra_hosts`:
```yaml
extra_hosts:
  - "imap.gmail.com:142.250.145.108"
```

**Option B:** In `.env`:
```bash
NODE_OPTIONS=--dns-result-order=ipv4first
```

Die IPv4-Adresse ermitteln:
```bash
dig +short imap.gmail.com A | head -1
```

---

## Sync-Frequenz anpassen

Die Cron-Syntax in `SYNC_FREQUENCY`:

```bash
# Alle 5 Minuten (Standard)
SYNC_FREQUENCY='*/5 * * * *'

# Alle 15 Minuten
SYNC_FREQUENCY='*/15 * * * *'

# Jede Stunde
SYNC_FREQUENCY='0 * * * *'

# Alle 2 Stunden
SYNC_FREQUENCY='0 */2 * * *'
```

---

## Firewall-Regeln

Ports die von aussen erreichbar sein muessen:

| Port | Dienst | Zugriff |
|------|--------|---------|
| 3000 | Web-UI | LAN / VPN |
| 445 | Samba (Maildrop) | LAN |

Ports die nur lokal benoetigt werden (127.0.0.1):

| Port | Dienst |
|------|--------|
| 4000 | Backend API |
| 5432 | PostgreSQL |
| 6379 | Valkey |
| 7700 | Meilisearch |
| 9998 | Apache Tika |
| 11143 | Proton TLS-Wrapper |

---

[Zurueck zur Startseite](./) | [Weiter: Architektur](architecture)

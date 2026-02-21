---
layout: default
title: Architektur
---

# Architektur

[Zurueck zur Startseite](./)

---

## Systemueberblick

```
                          ┌─────────────────────────┐
                          │      Benutzer            │
                          │  (Browser / PowerShell)  │
                          └──────────┬──────────────┘
                                     │
                              Port 3000 (HTTP)
                                     │
                          ┌──────────▼──────────────┐
                          │     OpenArchiver         │
                          │  ┌───────────────────┐   │
                          │  │    Frontend        │   │
                          │  │    (SvelteKit)     │   │
                          │  └────────┬──────────┘   │
                          │           │               │
                          │  ┌────────▼──────────┐   │
                          │  │    Backend         │   │
                          │  │    (Node.js)       │   │
                          │  │    Port 4000       │   │
                          │  └─┬──┬──┬──┬──┬─────┘   │
                          │    │  │  │  │  │          │
                          │    │  │  │  │  │ IMAP     │
                          └────┼──┼──┼──┼──┼──────────┘
                               │  │  │  │  │
          ┌────────────────────┘  │  │  │  └──────────────────┐
          │           ┌───────────┘  │  └──────────┐          │
          ▼           ▼              ▼              ▼          ▼
   ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
   │PostgreSQL│ │  Valkey   │ │  Meili-  │ │  Apache  │ │  IMAP-   │
   │          │ │ (Redis)   │ │  search  │ │  Tika    │ │  Server  │
   │ Metadata │ │ Job-Queue │ │ Volltext │ │ Text-    │ │ (extern) │
   │ Accounts │ │ Cache     │ │ Suche    │ │ Extrakt. │ │          │
   │ :5432    │ │ :6379     │ │ :7700    │ │ :9998    │ │ :993/143 │
   └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘
```

---

## Datenfluss

### 1. IMAP-Sync (automatisch)

```
IMAP-Server (Gmail, iCloud, etc.)
       │
       │ IMAP/SSL (:993)
       ▼
  OpenArchiver Backend
       │
       ├── Email-Metadaten ──────> PostgreSQL
       ├── Email-Body (AES-256) ─> Dateisystem (/var/data/open-archiver/)
       ├── Anhaenge ─────────────> Dateisystem (dedupliziert)
       ├── Anhang-Text ──────────> Apache Tika (Extraktion) ─> Meilisearch
       └── Volltext-Index ───────> Meilisearch
```

### 2. Proton Bridge (ueber TLS-Wrapper)

```
  Proton Bridge Docker
  (STARTTLS, Port 1143)
       │
       │ STARTTLS
       ▼
  socat TLS-Wrapper
  (SSL, Port 11143)
       │
       │ Implizites SSL
       ▼
  OpenArchiver Backend
  (Generic IMAP, secure=true)
```

**Warum ein TLS-Wrapper?**

Proton Bridge bietet IMAP nur mit STARTTLS an (Verbindung startet unverschluesselt, dann Upgrade). OpenArchivers IMAP-Library unterstuetzt STARTTLS nicht zuverlaessig. Der socat TLS-Wrapper uebersetzt:

- **Eingehend** (von OpenArchiver): Implizites SSL auf Port 11143
- **Ausgehend** (zu Bridge): Klartext TCP auf Port 1143

Das CA-Zertifikat wird via `NODE_EXTRA_CA_CERTS` in den Container gemountet.

### 3. Maildrop (Datei-Import)

```
  Windows/macOS/Linux Client
       │
       │ SMB/CIFS (Port 445)
       ▼
  Samba Share (/srv/maildrop/)
       │
       │ inotify-Polling (10s)
       ▼
  maildrop-watcher.sh
       │
       ├── Datei hochladen (POST /v1/upload)
       └── Import erstellen (POST /v1/ingestion-sources)
            │
            ▼
       OpenArchiver Backend
       (EML/PST/MBOX Parsing)
```

### 4. Windows PowerShell Import

```
  Windows PC (Outlook installiert)
       │
       │ Export-OutlookToOpenArchiver.ps1
       │
       ├── Outlook COM-Objekt ─> Account-Liste
       ├── Windows Registry ───> IMAP-Einstellungen
       ├── Benutzer-Eingabe ──> Passwoerter
       │
       │ REST API (HTTP)
       ▼
  OpenArchiver Backend
  (POST /v1/ingestion-sources)
```

---

## Docker-Netzwerk

```
┌─────────────────────────────────────────────────────┐
│  Host-Netzwerk (network_mode: host)                 │
│                                                     │
│  ┌───────────────────────────────────┐              │
│  │  open-archiver                    │              │
│  │  Lauscht auf: 0.0.0.0:3000       │              │
│  │               0.0.0.0:4000       │              │
│  └───────────────────────────────────┘              │
│                                                     │
│  ┌─────────────────────────────────────────────┐    │
│  │  Bridge-Netzwerk: oa-net                    │    │
│  │                                             │    │
│  │  postgres    127.0.0.1:5432 ─> :5432        │    │
│  │  valkey      127.0.0.1:6379 ─> :6379        │    │
│  │  meilisearch 127.0.0.1:7700 ─> :7700        │    │
│  │  tika        127.0.0.1:9998 ─> :9998        │    │
│  └─────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

OpenArchiver laeuft im **Host-Netzwerk** (`network_mode: host`), damit es direkt auf die Ports der anderen Container zugreifen kann. Die Support-Services (Postgres, Valkey, etc.) laufen in einem eigenen Bridge-Netzwerk und binden sich nur an `127.0.0.1`.

---

## Speicher-Layout

```
/data/openarchiver/storage/          # Host-Pfad (konfiguribar)
└── open-archiver/
    └── <email>-(<label>)-<source-id>/
        ├── emails/
        │   ├── <hash>.eml.enc      # Verschluesselte Email (AES-256)
        │   └── ...
        └── attachments/
            ├── <hash>-filename.ext  # Deduplizierte Anhaenge
            └── ...
```

- **Emails** werden mit AES-256 verschluesselt gespeichert (`STORAGE_ENCRYPTION_KEY`)
- **Anhaenge** werden dedupliziert (gleiche Datei = nur einmal gespeichert)
- **Metadaten** liegen in PostgreSQL (Absender, Betreff, Datum, Ordner, etc.)
- **Suchindex** liegt in Meilisearch (Volltext aus Body + Anhaengen via Tika)

---

## Verschluesselung

| Was | Wie | Key |
|-----|-----|-----|
| Gespeicherte Emails | AES-256 | `STORAGE_ENCRYPTION_KEY` |
| IMAP-Credentials (in DB) | AES-256 | `ENCRYPTION_KEY` |
| API-Authentifizierung | JWT (HMAC) | `JWT_SECRET` |
| IMAP-Verbindungen | SSL/TLS | Zertifikate der Provider |
| Proton Bridge | socat + CA-signed Cert | Lokale CA |

---

[Zurueck zur Startseite](./) | [Weiter: Proton Bridge](proton-bridge)

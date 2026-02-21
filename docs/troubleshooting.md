---
layout: default
title: Troubleshooting
---

# Troubleshooting

[Zurueck zur Startseite](./)

---

## Haeufige Probleme

### OpenArchiver startet nicht

```bash
# Logs pruefen
docker compose logs open-archiver

# Haeufigste Ursache: PostgreSQL nicht bereit
docker compose logs postgres

# Manuell neustarten
docker compose down && docker compose up -d
```

### "ECONNREFUSED" bei IMAP-Sync

**Symptom:** `connect ECONNREFUSED 10.x.x.x:993`

**Ursachen:**
- Falscher IMAP-Host in der Ingestion Source
- IMAP-Server nicht erreichbar
- Firewall blockiert Port 993

**Loesung:**
```bash
# Verbindung testen
openssl s_client -connect IMAP_HOST:993 </dev/null

# DNS pruefen
dig +short IMAP_HOST

# Aus dem Container heraus testen
docker exec open-archiver curl -v telnet://IMAP_HOST:993
```

### Gmail "ECONNRESET"

**Symptom:** Gmail IMAP-Verbindung wird sofort getrennt.

**Ursache:** Server hat IPv6 aber kein IPv6-Routing. Node.js versucht IPv6 zuerst.

**Loesung:** In `.env`:
```bash
NODE_OPTIONS=--dns-result-order=ipv4first
```

Oder in `docker-compose.yml`:
```yaml
extra_hosts:
  - "imap.gmail.com:142.250.145.108"
```

IPv4-Adresse ermitteln:
```bash
dig +short imap.gmail.com A | head -1
```

### Proton Bridge "No active accounts"

**Symptom:** Bridge laeuft aber zeigt keine Konten.

**Ursache:** Login-State verloren (Container neu erstellt, Update, etc.)

**Loesung:** Erneut einloggen:
```bash
docker exec -it proton-bridge bash
printf "login\nuser@protonmail.com\nPASSWORD\n" > /protonmail/faketty
```

### Proton Bridge crashed (libfido2.so.1)

**Symptom:** Container startet aber Bridge-Prozess crashed sofort.

**Ursache:** Auto-Update auf Version mit fehlenden Bibliotheken.

**Loesung:** In `docker-compose.proton.yml` den direkten Binary-Pfad verwenden:
```yaml
command:
  - |
    cat /protonmail/faketty | /usr/lib/protonmail/bridge/bridge --cli
```

### Proton TLS-Wrapper Verbindungsfehler

**Symptom:** OpenArchiver kann sich nicht mit Port 11143 verbinden.

```bash
# Wrapper-Status pruefen
sudo systemctl status proton-tls-wrapper

# SSL-Verbindung testen
openssl s_client -connect 127.0.0.1:11143 </dev/null 2>/dev/null | head -5

# Bridge erreichbar?
curl -v telnet://127.0.0.1:1143

# Zertifikat erneuern
sudo ./scripts/generate-tls-cert.sh
sudo systemctl restart proton-tls-wrapper
docker compose restart open-archiver
```

### Maildrop-Watcher importiert nicht

```bash
# Service-Status
sudo systemctl status maildrop-watcher

# Log pruefen
sudo journalctl -u maildrop-watcher -n 50

# Haeufige Ursachen:
# 1. OpenArchiver-Credentials falsch
# 2. OpenArchiver noch nicht gestartet
# 3. Datei in falschem Format (nur .zip/.pst/.mbox)
```

### Meilisearch Speicher voll

**Symptom:** Suche funktioniert nicht, Meilisearch crashed.

```bash
# Speicher pruefen
docker exec oa-meilisearch df -h /meili_data

# Index-Groesse
docker exec oa-meilisearch du -sh /meili_data/

# Bei Bedarf: Index zuruecksetzen (Emails werden neu indexiert)
docker compose stop meilisearch
docker volume rm $(docker volume ls -q | grep meili)
docker compose up -d
```

### Tika "422 Unprocessable Entity"

**Symptom:** Tika kann bestimmte Anhaenge nicht verarbeiten.

**Ursache:** Korrupte oder nicht unterstuetzte Datei (z.B. verschluesseltes PDF).

**Loesung:** Das ist normal und kann ignoriert werden. Der Email-Body wird trotzdem indexiert. Nur der Anhang-Text fehlt im Suchindex.

### PostgreSQL Healthcheck Failed

```bash
# Logs pruefen
docker compose logs postgres

# Manuell testen
docker exec oa-postgres pg_isready -U archiver

# Haeufig: Falsches Passwort in DATABASE_URL vs POSTGRES_PASSWORD
# Beide muessen identisch sein!
```

---

## Diagnose-Befehle

### Container-Status

```bash
docker compose ps
docker compose logs -f        # Alle Logs live
docker compose logs -f open-archiver  # Nur OA
```

### API testen

```bash
# Login
TOKEN=$(curl -s -X POST http://localhost:4000/v1/auth/login \
  -H "Content-Type: application/json" \
  -d @- <<'EOF' | python3 -c "import sys,json; print(json.load(sys.stdin).get('accessToken',''))"
{"email":"admin@example.com","password":"YOUR_PASSWORD"}
EOF
)

# Quellen auflisten
curl -s http://localhost:4000/v1/ingestion-sources \
  -H "authorization: Bearer $TOKEN" | python3 -m json.tool

# Sync erzwingen
curl -s -X POST http://localhost:4000/v1/ingestion-sources/SOURCE_ID/sync \
  -H "authorization: Bearer $TOKEN"
```

### Speicher pruefen

```bash
# Host-Speicher
du -sh /data/openarchiver/storage/

# Docker-Volumes
docker system df -v | grep -E "pgdata|valkey|meili"

# Gesamter Docker-Speicher
docker system df
```

### Netzwerk testen

```bash
# IMAP-Verbindung (extern)
openssl s_client -connect imap.gmail.com:993 </dev/null 2>/dev/null | head -3

# IMAP-Verbindung (Proton TLS-Wrapper)
openssl s_client -connect 127.0.0.1:11143 </dev/null 2>/dev/null | head -3

# DNS-Aufloesung im Container
docker exec open-archiver getent hosts imap.gmail.com
```

---

## Backup & Restore

### Backup

```bash
# 1. Stack stoppen (konsistenter Zustand)
docker compose down

# 2. PostgreSQL-Dump
docker compose up -d postgres
docker exec oa-postgres pg_dump -U archiver open_archive > backup_db.sql
docker compose down

# 3. Dateisystem sichern
tar czf backup_storage.tar.gz -C /data/openarchiver storage/

# 4. Konfiguration sichern
cp .env backup.env
```

### Restore

```bash
# 1. .env wiederherstellen
cp backup.env .env

# 2. Speicher wiederherstellen
tar xzf backup_storage.tar.gz -C /data/openarchiver/

# 3. Stack starten
docker compose up -d

# 4. DB-Dump wiederherstellen
docker exec -i oa-postgres psql -U archiver open_archive < backup_db.sql

# 5. Meilisearch-Index wird automatisch neu aufgebaut
```

---

[Zurueck zur Startseite](./)

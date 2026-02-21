---
layout: default
title: Windows-Import
---

# Windows PowerShell Import

[Zurueck zur Startseite](./)

---

## Uebersicht

Zwei PowerShell-Skripte erleichtern den Import von Outlook-Konten in OpenArchiver:

| Skript | Funktion |
|--------|----------|
| `Export-OutlookToOpenArchiver.ps1` | Liest Outlook-Konten, fragt Passwoerter ab, erstellt IMAP-Quellen in OpenArchiver |
| `Export-OutlookCredentials.ps1` | Exportiert Konto-Details und sucht gespeicherte Passwoerter (DPAPI, Credential Manager) |

---

## Export-OutlookToOpenArchiver.ps1

### Was macht das Skript?

1. Liest alle Outlook-Konten aus (COM-Objekt + Windows Registry)
2. Erkennt IMAP-Einstellungen automatisch fuer 25+ Provider
3. Fragt Passwoerter ab (mit Hinweis auf App-Passwoerter)
4. Exportiert Account-Liste als JSON (ohne Passwoerter)
5. Erstellt IMAP-Quellen in OpenArchiver per REST API

### Verwendung

```powershell
# Direkt in OpenArchiver importieren
.\Export-OutlookToOpenArchiver.ps1 -OpenArchiverUrl "http://SERVER_IP:3000"

# Nur JSON-Export (ohne Import)
.\Export-OutlookToOpenArchiver.ps1 -ExportOnly
```

### Ablauf

```
1. Outlook-Konten lesen (COM + Registry)
   └── Gefunden: user@gmail.com, user@outlook.com, ...

2. Pro Konto: Review + Passwort
   ├── IMAP-Server automatisch erkannt
   ├── [J]a / [E]ditieren / [S]kip
   └── Passwort eingeben (App-Password empfohlen!)

3. JSON-Backup erstellen
   └── outlook-accounts_2026-02-21_143022.json

4. OpenArchiver-Login (Email + Passwort)

5. IMAP-Quellen erstellen
   ├── user@gmail.com -> Erstellt! Status: auth_success
   └── user@outlook.com -> Erstellt! Status: auth_success
```

### Unterstuetzte Provider (Auto-Detect)

Das Skript erkennt automatisch die IMAP-Einstellungen fuer:

- Gmail / Googlemail
- iCloud / me.com
- Outlook.com / Hotmail / Live
- GMX
- Web.de
- T-Online
- Freenet
- Posteo
- Mailbox.org
- Yahoo
- AOL
- IONOS / 1&1
- Strato
- Office 365

Fuer unbekannte Domains wird `imap.<domain>:993` angenommen.

---

## Export-OutlookCredentials.ps1

### Was macht das Skript?

Versucht gespeicherte Passwoerter zu finden - nuetzlich wenn man die Passwoerter nicht mehr weiss:

1. **Outlook Registry** - DPAPI-verschluesselte Passwoerter entschluesseln
2. **Windows Credential Manager** - Gespeicherte Mail-Credentials suchen
3. **Proton Bridge** - Lokale Bridge-Konfiguration pruefen

### Verwendung

```powershell
# Nur Mail-relevante Credentials
.\Export-OutlookCredentials.ps1

# ALLE Credential-Manager-Eintraege anzeigen
.\Export-OutlookCredentials.ps1 -DumpAllCredentials
```

### Wichtige Hinweise

- **Als normaler User ausfuehren** (NICHT als Admin!) - DPAPI funktioniert nur im User-Kontext
- **OAuth2-Konten** (Gmail, iCloud, Outlook.com) haben KEIN lokales Passwort - hier App-Passwoerter erstellen
- Die JSON-Ausgabe kann Klartext-Passwoerter enthalten - **nach Verwendung sicher loeschen!**

---

## App-Passwoerter erstellen

Fuer Konten mit 2-Faktor-Authentifizierung:

### Google (Gmail)

1. [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords) oeffnen
2. App-Name eingeben (z.B. "OpenArchiver")
3. 16-Zeichen-Passwort kopieren

### Apple (iCloud)

1. [appleid.apple.com](https://appleid.apple.com) > Anmelden
2. Sicherheit > App-spezifische Passwoerter
3. Passwort generieren

### Microsoft (Outlook.com/Hotmail)

1. [account.live.com/proofs/AppPassword](https://account.live.com/proofs/AppPassword)
2. 2FA muss aktiviert sein
3. Passwort generieren

### ProtonMail

ProtonMail verwendet keine App-Passwoerter. Stattdessen:
1. Proton Bridge starten
2. Konto-Details anzeigen
3. Bridge-Passwort verwenden

Siehe [Proton Bridge Dokumentation](proton-bridge) fuer Details.

---

## PST-Import

PST-Dateien koennen nicht per Skript importiert werden, sondern:

### Option A: Web-UI

1. OpenArchiver oeffnen (`http://SERVER:3000`)
2. Ingestion Sources > New > **PST Import**
3. PST-Datei hochladen

### Option B: Maildrop-Share

1. PST-Datei in `\\SERVER\maildrop` kopieren
2. Der Maildrop-Watcher importiert automatisch

Siehe [Maildrop-Dokumentation](maildrop).

---

[Zurueck zur Startseite](./) | [Weiter: NFS-Migration](nfs-migration)

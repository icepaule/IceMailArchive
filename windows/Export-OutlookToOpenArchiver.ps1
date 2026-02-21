#Requires -Version 5.1
<#
.SYNOPSIS
    Exports Outlook email account settings and imports them into OpenArchiver.

.DESCRIPTION
    1. Reads all configured email accounts from Outlook (COM + Registry)
    2. Auto-detects IMAP settings for common providers (Gmail, Outlook.com, GMX, Web.de, etc.)
    3. Lets you review/edit settings and enter passwords (app passwords recommended!)
    4. Exports accounts to JSON file (local backup)
    5. Creates IMAP ingestion sources in OpenArchiver via REST API

.PARAMETER OpenArchiverUrl
    Base URL of OpenArchiver instance (e.g. http://192.168.1.100:3000)

.PARAMETER ExportOnly
    Only export account settings to JSON, don't push to OpenArchiver

.EXAMPLE
    .\Export-OutlookToOpenArchiver.ps1 -OpenArchiverUrl "http://192.168.1.100:3000"

.EXAMPLE
    .\Export-OutlookToOpenArchiver.ps1 -ExportOnly

.NOTES
    - Outlook passwords CANNOT be extracted (Windows encrypts them)
    - You'll be prompted for each account's password / app password
    - For Gmail/Outlook.com: Use App Passwords for security!
    - PST files found in Outlook profile are listed for manual upload
#>

[CmdletBinding()]
param(
    [string]$OpenArchiverUrl = "http://YOUR_SERVER_IP:3000",
    [switch]$ExportOnly
)

$ErrorActionPreference = "Stop"

# --- Well-known IMAP settings for common providers ---
$ImapProviders = @{
    "outlook.com"    = @{ Host = "outlook.office365.com";  Port = 993; Secure = $true; Note = "App Password: https://account.live.com/proofs/AppPassword" }
    "hotmail.com"    = @{ Host = "outlook.office365.com";  Port = 993; Secure = $true; Note = "App Password: https://account.live.com/proofs/AppPassword" }
    "hotmail.de"     = @{ Host = "outlook.office365.com";  Port = 993; Secure = $true; Note = "App Password: https://account.live.com/proofs/AppPassword" }
    "live.com"       = @{ Host = "outlook.office365.com";  Port = 993; Secure = $true; Note = "App Password: https://account.live.com/proofs/AppPassword" }
    "live.de"        = @{ Host = "outlook.office365.com";  Port = 993; Secure = $true; Note = "App Password: https://account.live.com/proofs/AppPassword" }
    "msn.com"        = @{ Host = "outlook.office365.com";  Port = 993; Secure = $true; Note = "App Password via M365 Admin" }
    "office365.com"  = @{ Host = "outlook.office365.com";  Port = 993; Secure = $true; Note = "App Password via M365 Admin" }
    "gmail.com"      = @{ Host = "imap.gmail.com";         Port = 993; Secure = $true; Note = "App Password: https://myaccount.google.com/apppasswords" }
    "googlemail.com" = @{ Host = "imap.gmail.com";         Port = 993; Secure = $true; Note = "App Password: https://myaccount.google.com/apppasswords" }
    "gmx.de"         = @{ Host = "imap.gmx.net";           Port = 993; Secure = $true; Note = "IMAP muss in GMX Einstellungen aktiviert sein!" }
    "gmx.net"        = @{ Host = "imap.gmx.net";           Port = 993; Secure = $true; Note = "IMAP muss in GMX Einstellungen aktiviert sein!" }
    "gmx.at"         = @{ Host = "imap.gmx.net";           Port = 993; Secure = $true; Note = "IMAP muss in GMX Einstellungen aktiviert sein!" }
    "gmx.ch"         = @{ Host = "imap.gmx.net";           Port = 993; Secure = $true; Note = "IMAP muss in GMX Einstellungen aktiviert sein!" }
    "web.de"         = @{ Host = "imap.web.de";            Port = 993; Secure = $true; Note = "IMAP muss in Web.de Einstellungen aktiviert sein!" }
    "t-online.de"    = @{ Host = "secureimap.t-online.de"; Port = 993; Secure = $true; Note = "App Password im Kundencenter erstellen" }
    "freenet.de"     = @{ Host = "mx.freenet.de";          Port = 993; Secure = $true; Note = "IMAP in Freenet Einstellungen aktivieren" }
    "posteo.de"      = @{ Host = "posteo.de";              Port = 993; Secure = $true; Note = "Normales Passwort verwenden" }
    "mailbox.org"    = @{ Host = "imap.mailbox.org";       Port = 993; Secure = $true; Note = "Normales Passwort oder App Password" }
    "icloud.com"     = @{ Host = "imap.mail.me.com";       Port = 993; Secure = $true; Note = "App Password: https://appleid.apple.com" }
    "me.com"         = @{ Host = "imap.mail.me.com";       Port = 993; Secure = $true; Note = "App Password: https://appleid.apple.com" }
    "yahoo.com"      = @{ Host = "imap.mail.yahoo.com";    Port = 993; Secure = $true; Note = "App Password in Yahoo Sicherheitseinstellungen" }
    "yahoo.de"       = @{ Host = "imap.mail.yahoo.com";    Port = 993; Secure = $true; Note = "App Password in Yahoo Sicherheitseinstellungen" }
    "aol.com"        = @{ Host = "imap.aol.com";           Port = 993; Secure = $true; Note = "App Password in AOL Sicherheitseinstellungen" }
    "ionos.de"       = @{ Host = "imap.ionos.de";          Port = 993; Secure = $true; Note = "Normales Passwort verwenden" }
    "1und1.de"       = @{ Host = "imap.1und1.de";          Port = 993; Secure = $true; Note = "Normales Passwort verwenden" }
    "strato.de"      = @{ Host = "imap.strato.de";         Port = 993; Secure = $true; Note = "Normales Passwort verwenden" }
}

# ============================================================================
# STEP 1: Extract accounts from Outlook
# ============================================================================

function Get-OutlookAccountsFromCOM {
    $accounts = @()
    try {
        Write-Host "`n[COM] Verbinde mit Outlook..." -ForegroundColor Cyan
        $outlook = New-Object -ComObject Outlook.Application
        $namespace = $outlook.GetNamespace("MAPI")

        foreach ($account in $namespace.Accounts) {
            $accounts += [PSCustomObject]@{
                DisplayName = $account.DisplayName
                Email       = $account.SmtpAddress
                AccountType = $account.AccountType
                UserName    = $account.UserName
                Source      = "COM"
            }
            Write-Host "  Gefunden: $($account.SmtpAddress) ($($account.DisplayName))" -ForegroundColor Green
        }

        Write-Host "`n[COM] Suche PST-Dateien in Outlook Profil..." -ForegroundColor Cyan
        foreach ($store in $namespace.Stores) {
            if ($store.FilePath -match '\.pst$') {
                Write-Host "  PST: $($store.FilePath) ($($store.DisplayName))" -ForegroundColor Yellow
            }
        }

        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($outlook) | Out-Null
    }
    catch {
        Write-Warning "[COM] Outlook COM nicht verfuegbar: $($_.Exception.Message)"
        Write-Warning "      (Outlook muss installiert sein)"
    }
    return $accounts
}

function Get-OutlookAccountsFromRegistry {
    $accounts = @()
    $officeVersions = @("16.0", "15.0")
    $profilesFound = $false

    foreach ($ver in $officeVersions) {
        $profileRoot = "HKCU:\Software\Microsoft\Office\$ver\Outlook\Profiles"
        if (-not (Test-Path $profileRoot)) { continue }

        $profilesFound = $true
        Write-Host "`n[Registry] Lese Outlook $ver Profile..." -ForegroundColor Cyan

        foreach ($profile in Get-ChildItem $profileRoot) {
            $accountKeyPath = Join-Path $profile.PSPath "9375CFF0413111d3B88A00104B2A6676"
            if (-not (Test-Path $accountKeyPath)) { continue }

            foreach ($subkey in Get-ChildItem $accountKeyPath -ErrorAction SilentlyContinue) {
                $props = Get-ItemProperty -Path $subkey.PSPath -ErrorAction SilentlyContinue

                $email = $null
                foreach ($propName in @("Account Name", "Email", "IMAP User", "POP3 User")) {
                    $val = $props.$propName
                    if ($val) {
                        if ($val -is [byte[]]) {
                            $val = [System.Text.Encoding]::Unicode.GetString($val).TrimEnd("`0")
                        }
                        if ($val -match "@") { $email = $val; break }
                    }
                }
                if (-not $email) { continue }

                $imapServer = $null; $imapPort = $null
                foreach ($serverProp in @("IMAP Server", "POP3 Server")) {
                    $val = $props.$serverProp
                    if ($val) {
                        if ($val -is [byte[]]) {
                            $val = [System.Text.Encoding]::Unicode.GetString($val).TrimEnd("`0")
                        }
                        $imapServer = $val; break
                    }
                }
                foreach ($portProp in @("IMAP Port", "POP3 Port")) {
                    $val = $props.$portProp
                    if ($val) { $imapPort = $val; break }
                }

                $displayName = $null
                $val = $props."Display Name"
                if ($val) {
                    if ($val -is [byte[]]) {
                        $val = [System.Text.Encoding]::Unicode.GetString($val).TrimEnd("`0")
                    }
                    $displayName = $val
                }

                $accounts += [PSCustomObject]@{
                    DisplayName = if ($displayName) { $displayName } else { $email }
                    Email       = $email
                    ImapServer  = $imapServer
                    ImapPort    = $imapPort
                    Source      = "Registry"
                }
                Write-Host "  Gefunden: $email $(if($imapServer){"($imapServer:$imapPort)"})" -ForegroundColor Green
            }
        }
    }

    if (-not $profilesFound) {
        Write-Warning "[Registry] Keine Outlook Profile in Registry gefunden"
    }
    return $accounts
}

function Get-ImapSettings {
    param(
        [string]$Email,
        [string]$RegistryServer,
        [int]$RegistryPort
    )

    $domain = ($Email -split "@")[1].ToLower()

    if ($RegistryServer) {
        return @{
            Host   = $RegistryServer
            Port   = if ($RegistryPort) { $RegistryPort } else { 993 }
            Secure = $true
            Note   = "Aus Outlook Registry"
        }
    }

    if ($ImapProviders.ContainsKey($domain)) {
        return $ImapProviders[$domain]
    }

    return @{
        Host   = "imap.$domain"
        Port   = 993
        Secure = $true
        Note   = "Auto-detect (bitte pruefen!)"
    }
}

# ============================================================================
# STEP 2: Collect and merge accounts
# ============================================================================

Write-Host "============================================================" -ForegroundColor White
Write-Host " Outlook -> OpenArchiver Export" -ForegroundColor White
Write-Host " Liest Outlook-Konten und importiert sie in OpenArchiver" -ForegroundColor Gray
Write-Host "============================================================`n" -ForegroundColor White

$comAccounts = Get-OutlookAccountsFromCOM
$regAccounts = Get-OutlookAccountsFromRegistry

$allEmails = @{}
foreach ($acc in ($comAccounts + $regAccounts)) {
    $key = $acc.Email.ToLower()
    if (-not $allEmails.ContainsKey($key)) {
        $allEmails[$key] = @{
            Email       = $acc.Email
            DisplayName = $acc.DisplayName
            ImapServer  = $null
            ImapPort    = $null
        }
    }
    if ($acc.PSObject.Properties.Name -contains "ImapServer" -and $acc.ImapServer) {
        $allEmails[$key].ImapServer = $acc.ImapServer
        $allEmails[$key].ImapPort = $acc.ImapPort
    }
    if ($acc.DisplayName -and $acc.DisplayName -ne $acc.Email) {
        $allEmails[$key].DisplayName = $acc.DisplayName
    }
}

if ($allEmails.Count -eq 0) {
    Write-Host "`nKeine Outlook-Konten gefunden!" -ForegroundColor Red
    Write-Host "Stellen Sie sicher, dass Outlook installiert und konfiguriert ist." -ForegroundColor Yellow
    exit 1
}

# ============================================================================
# STEP 3: Review accounts and collect passwords
# ============================================================================

Write-Host "`n============================================================" -ForegroundColor White
Write-Host " Gefundene Konten: $($allEmails.Count)" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White

$exportAccounts = @()
$index = 0

foreach ($entry in $allEmails.GetEnumerator() | Sort-Object Key) {
    $index++
    $acc = $entry.Value
    $imap = Get-ImapSettings -Email $acc.Email -RegistryServer $acc.ImapServer -RegistryPort $acc.ImapPort

    Write-Host "`n--- Konto $index/$($allEmails.Count): $($acc.Email) ---" -ForegroundColor Cyan
    Write-Host "  Name:        $($acc.DisplayName)"
    Write-Host "  IMAP Server: $($imap.Host):$($imap.Port) $(if($imap.Secure){'(SSL/TLS)'})"
    if ($imap.Note) { Write-Host "  Hinweis:     $($imap.Note)" -ForegroundColor Yellow }

    $confirm = Read-Host "`n  Importieren? ([J]a / [E]ditieren / [S]kip)"
    if ($confirm -match "^[Ss]") {
        Write-Host "  >> Uebersprungen" -ForegroundColor DarkGray
        continue
    }

    $host_ = $imap.Host
    $port_ = $imap.Port
    $secure_ = $imap.Secure
    $username_ = $acc.Email

    if ($confirm -match "^[Ee]") {
        $input = Read-Host "  IMAP Host [$host_]"
        if ($input) { $host_ = $input }
        $input = Read-Host "  IMAP Port [$port_]"
        if ($input) { $port_ = [int]$input }
        $input = Read-Host "  Username [$username_]"
        if ($input) { $username_ = $input }
        $input = Read-Host "  SSL/TLS (true/false) [$secure_]"
        if ($input) { $secure_ = [bool]($input -eq "true") }
    }

    Write-Host ""
    if ($imap.Note -match "App Password") {
        Write-Host "  EMPFOHLEN: App Password verwenden!" -ForegroundColor Yellow
        Write-Host "  $($imap.Note)" -ForegroundColor Yellow
    }
    $secPassword = Read-Host "  Passwort fuer $username_" -AsSecureString
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPassword)
    )

    if (-not $password) {
        Write-Host "  >> Kein Passwort, uebersprungen" -ForegroundColor DarkGray
        continue
    }

    $exportAccounts += [PSCustomObject]@{
        Name     = "$($acc.DisplayName) ($($acc.Email))"
        Email    = $acc.Email
        Host     = $host_
        Port     = $port_
        Username = $username_
        Password = $password
        Secure   = $secure_
    }
    Write-Host "  >> Hinzugefuegt" -ForegroundColor Green
}

if ($exportAccounts.Count -eq 0) {
    Write-Host "`nKeine Konten zum Exportieren ausgewaehlt." -ForegroundColor Yellow
    exit 0
}

# ============================================================================
# STEP 4: Export to JSON (local backup, without passwords)
# ============================================================================

$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$jsonPath = Join-Path $PSScriptRoot "outlook-accounts_$timestamp.json"

$safeExport = $exportAccounts | ForEach-Object {
    [PSCustomObject]@{
        Name     = $_.Name
        Email    = $_.Email
        Host     = $_.Host
        Port     = $_.Port
        Username = $_.Username
        Secure   = $_.Secure
    }
}
$safeExport | ConvertTo-Json -Depth 3 | Set-Content -Path $jsonPath -Encoding UTF8
Write-Host "`nKonten exportiert nach: $jsonPath (ohne Passwoerter)" -ForegroundColor Green

# ============================================================================
# STEP 5: Push to OpenArchiver
# ============================================================================

if ($ExportOnly) {
    Write-Host "`n-ExportOnly: Ueberspringe OpenArchiver Import." -ForegroundColor Yellow
    $fullPath = Join-Path $PSScriptRoot "outlook-accounts-FULL_$timestamp.json"
    $exportAccounts | ConvertTo-Json -Depth 3 | Set-Content -Path $fullPath -Encoding UTF8
    Write-Host "Vollstaendiger Export (MIT Passwoertern): $fullPath" -ForegroundColor Yellow
    Write-Host "WARNUNG: Diese Datei enthaelt Passwoerter! Sicher aufbewahren!" -ForegroundColor Red
    exit 0
}

Write-Host "`n============================================================" -ForegroundColor White
Write-Host " OpenArchiver Import: $OpenArchiverUrl" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White

Write-Host "`nOpenArchiver Login:" -ForegroundColor Cyan
$oaEmail = Read-Host "  Email"
$oaSecPw = Read-Host "  Passwort" -AsSecureString
$oaPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($oaSecPw)
)

try {
    $loginBody = @{
        email    = $oaEmail
        password = $oaPassword
    } | ConvertTo-Json

    $loginResponse = Invoke-RestMethod -Uri "$OpenArchiverUrl/api/v1/auth/login" `
        -Method POST `
        -ContentType "application/json" `
        -Body $loginBody

    $token = $loginResponse.accessToken
    Write-Host "  Login erfolgreich! (User: $($loginResponse.user.email))" -ForegroundColor Green
}
catch {
    Write-Host "  Login fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Haben Sie bereits einen Account unter $OpenArchiverUrl erstellt?" -ForegroundColor Yellow
    exit 1
}

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}

$created = 0
$failed = 0

foreach ($acc in $exportAccounts) {
    Write-Host "`nErstelle: $($acc.Name)..." -ForegroundColor Cyan

    $body = @{
        name           = $acc.Name
        provider       = "generic_imap"
        providerConfig = @{
            host              = $acc.Host
            port              = $acc.Port
            username          = $acc.Username
            password          = $acc.Password
            secure            = $acc.Secure
            allowInsecureCert = $false
        }
    } | ConvertTo-Json -Depth 3

    try {
        $response = Invoke-RestMethod -Uri "$OpenArchiverUrl/api/v1/ingestion-sources" `
            -Method POST `
            -Headers $headers `
            -Body $body

        Write-Host "  Erstellt! Status: $($response.status)" -ForegroundColor Green
        $created++
    }
    catch {
        $errMsg = $_.Exception.Message
        try {
            $errBody = $_.ErrorDetails.Message | ConvertFrom-Json
            $errMsg = $errBody.message
        } catch {}
        Write-Host "  FEHLER: $errMsg" -ForegroundColor Red
        $failed++
    }
}

# ============================================================================
# Summary
# ============================================================================

Write-Host "`n============================================================" -ForegroundColor White
Write-Host " Zusammenfassung" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White
Write-Host "  Erstellt:       $created" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "  Fehlgeschlagen: $failed" -ForegroundColor Red
}
Write-Host "  JSON Backup:    $jsonPath"
Write-Host ""
Write-Host "  OpenArchiver GUI: $OpenArchiverUrl" -ForegroundColor Cyan
Write-Host "  Der IMAP-Sync startet automatisch alle 5 Minuten." -ForegroundColor Gray
Write-Host ""
Write-Host "  TIPP: PST-Dateien manuell in der GUI importieren:" -ForegroundColor Yellow
Write-Host "  Ingestion Sources -> New -> PST Import -> Datei hochladen" -ForegroundColor Yellow

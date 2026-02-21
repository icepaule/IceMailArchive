#Requires -Version 5.1
<#
.SYNOPSIS
    Exportiert Outlook-Kontodaten und versucht gespeicherte Passwoerter zu finden.

.DESCRIPTION
    Liest Outlook-Konto-Credentials aus mehreren Quellen:
    1. Outlook Registry Profile (Kontoeinstellungen + DPAPI)
    2. Windows Credential Manager - ALLE Eintraege (breite Suche)
    3. Proton Bridge Credentials (falls installiert)

.PARAMETER OutputFile
    Pfad fuer die JSON-Ausgabedatei

.PARAMETER DumpAllCredentials
    Zeigt ALLE Eintraege im Credential Manager (nicht nur Mail-bezogene)

.EXAMPLE
    .\Export-OutlookCredentials.ps1
    .\Export-OutlookCredentials.ps1 -DumpAllCredentials

.NOTES
    - Als normaler User ausfuehren (nicht als Admin!)
    - Neues Outlook nutzt OAuth2 - da sind keine Passwoerter lokal gespeichert
    - Fuer OAuth2-Konten (Gmail, iCloud, Outlook.com) App-Passwoerter erstellen
#>

[CmdletBinding()]
param(
    [string]$OutputFile,
    [switch]$DumpAllCredentials
)

$ErrorActionPreference = "Continue"
Add-Type -AssemblyName System.Security

# ============================================================================
# Bekannte IMAP-Settings pro Provider
# ============================================================================

$ImapProviders = @{
    "gmail.com"       = @{ Host="imap.gmail.com";          Port=993; AppPwUrl="https://myaccount.google.com/apppasswords"; Note="Google App Password noetig (2FA muss aktiv sein)" }
    "googlemail.com"  = @{ Host="imap.gmail.com";          Port=993; AppPwUrl="https://myaccount.google.com/apppasswords"; Note="Google App Password noetig" }
    "icloud.com"      = @{ Host="imap.mail.me.com";        Port=993; AppPwUrl="https://appleid.apple.com/account/manage/section/security"; Note="Apple App Password noetig" }
    "me.com"          = @{ Host="imap.mail.me.com";        Port=993; AppPwUrl="https://appleid.apple.com/account/manage/section/security"; Note="Apple App Password noetig" }
    "protonmail.com"  = @{ Host="127.0.0.1";               Port=1143; AppPwUrl=$null; Note="Proton Bridge lokaler IMAP (Bridge muss laufen!)" }
    "proton.me"       = @{ Host="127.0.0.1";               Port=1143; AppPwUrl=$null; Note="Proton Bridge lokaler IMAP" }
    "outlook.com"     = @{ Host="outlook.office365.com";   Port=993; AppPwUrl="https://account.live.com/proofs/AppPassword"; Note="Microsoft App Password noetig" }
    "hotmail.com"     = @{ Host="outlook.office365.com";   Port=993; AppPwUrl="https://account.live.com/proofs/AppPassword"; Note="Microsoft App Password noetig" }
    "hotmail.de"      = @{ Host="outlook.office365.com";   Port=993; AppPwUrl="https://account.live.com/proofs/AppPassword"; Note="Microsoft App Password noetig" }
    "live.com"        = @{ Host="outlook.office365.com";   Port=993; AppPwUrl="https://account.live.com/proofs/AppPassword"; Note="Microsoft App Password noetig" }
    "live.de"         = @{ Host="outlook.office365.com";   Port=993; AppPwUrl="https://account.live.com/proofs/AppPassword"; Note="Microsoft App Password noetig" }
    "gmx.de"          = @{ Host="imap.gmx.net";            Port=993; AppPwUrl=$null; Note="Normales Passwort; IMAP in GMX aktivieren!" }
    "gmx.net"         = @{ Host="imap.gmx.net";            Port=993; AppPwUrl=$null; Note="Normales Passwort; IMAP in GMX aktivieren!" }
    "web.de"          = @{ Host="imap.web.de";             Port=993; AppPwUrl=$null; Note="Normales Passwort; IMAP in Web.de aktivieren!" }
    "t-online.de"     = @{ Host="secureimap.t-online.de";  Port=993; AppPwUrl="https://email.t-online.de/sicherheit"; Note="T-Online App Password im Kundencenter" }
    "posteo.de"       = @{ Host="posteo.de";               Port=993; AppPwUrl=$null; Note="Normales Passwort verwenden" }
    "mailbox.org"     = @{ Host="imap.mailbox.org";        Port=993; AppPwUrl=$null; Note="Normales Passwort verwenden" }
    "freenet.de"      = @{ Host="mx.freenet.de";           Port=993; AppPwUrl=$null; Note="IMAP in Freenet Einstellungen aktivieren" }
    "yahoo.com"       = @{ Host="imap.mail.yahoo.com";     Port=993; AppPwUrl=$null; Note="App Password in Yahoo Sicherheitseinstellungen" }
    "ionos.de"        = @{ Host="imap.ionos.de";           Port=993; AppPwUrl=$null; Note="Normales Passwort verwenden" }
    "1und1.de"        = @{ Host="imap.1und1.de";           Port=993; AppPwUrl=$null; Note="Normales Passwort verwenden" }
    "strato.de"       = @{ Host="imap.strato.de";          Port=993; AppPwUrl=$null; Note="Normales Passwort verwenden" }
}

# ============================================================================
# Hilfsfunktionen
# ============================================================================

function ConvertFrom-RegistryBinary {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return $Value }
    if ($Value -is [int]) { return $Value }
    if ($Value -is [byte[]]) {
        $text = [System.Text.Encoding]::Unicode.GetString($Value).TrimEnd("`0")
        if ([string]::IsNullOrWhiteSpace($text) -or $text -match '[\x00-\x08\x0E-\x1F]') {
            $text = [System.Text.Encoding]::UTF8.GetString($Value).TrimEnd("`0")
        }
        return $text
    }
    return $Value.ToString()
}

function Unprotect-DpapiBlob {
    param([byte[]]$EncryptedBytes)
    try {
        $decrypted = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $EncryptedBytes, $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        $text = [System.Text.Encoding]::Unicode.GetString($decrypted).TrimEnd("`0")
        if ($text -match '[\x00-\x08\x0E-\x1F]') {
            $text = [System.Text.Encoding]::UTF8.GetString($decrypted).TrimEnd("`0")
        }
        return $text
    }
    catch { return $null }
}

# ============================================================================
# Quelle 1: Outlook Registry
# ============================================================================

function Get-OutlookRegistryAccounts {
    Write-Host "`n[1/3] Outlook Registry Profile..." -ForegroundColor Cyan

    $accounts = @()

    foreach ($ver in @("16.0", "15.0")) {
        $profileRoot = "HKCU:\Software\Microsoft\Office\$ver\Outlook\Profiles"
        if (-not (Test-Path $profileRoot)) { continue }

        Write-Host "  Outlook $ver gefunden" -ForegroundColor Gray

        foreach ($profile in Get-ChildItem $profileRoot) {
            $accountKeyPath = Join-Path $profile.PSPath "9375CFF0413111d3B88A00104B2A6676"
            if (-not (Test-Path $accountKeyPath)) { continue }

            foreach ($subkey in Get-ChildItem $accountKeyPath -ErrorAction SilentlyContinue) {
                $props = Get-ItemProperty -Path $subkey.PSPath -ErrorAction SilentlyContinue
                if (-not $props) { continue }

                $email = $null
                foreach ($propName in @("Account Name", "Email", "IMAP User", "POP3 User",
                                        "001f6607", "001f3001", "001f6641")) {
                    $val = $props.$propName
                    if ($val) {
                        $val = ConvertFrom-RegistryBinary $val
                        if ($val -match "@") { $email = $val; break }
                    }
                }
                if (-not $email) { continue }

                $displayName = ConvertFrom-RegistryBinary $props."Display Name"
                $imapServer  = ConvertFrom-RegistryBinary $props."IMAP Server"
                $pop3Server  = ConvertFrom-RegistryBinary $props."POP3 Server"
                $smtpServer  = ConvertFrom-RegistryBinary $props."SMTP Server"
                $imapPort    = $props."IMAP Port"
                $pop3Port    = $props."POP3 Port"
                $smtpPort    = $props."SMTP Port"
                $imapUser    = ConvertFrom-RegistryBinary $props."IMAP User"
                $pop3User    = ConvertFrom-RegistryBinary $props."POP3 User"

                $password = $null; $pwSource = $null
                foreach ($pwProp in @("IMAP Password", "POP3 Password", "SMTP Password",
                                      "HTTPMail Password", "HTTP Password")) {
                    $pwBytes = $props.$pwProp
                    if ($pwBytes -is [byte[]] -and $pwBytes.Length -gt 0) {
                        $dec = Unprotect-DpapiBlob -EncryptedBytes $pwBytes
                        if ($dec -and $dec.Length -gt 0) {
                            $password = $dec; $pwSource = "DPAPI ($pwProp)"; break
                        }
                    }
                }

                if (-not $password) {
                    $allPropNames = $props.PSObject.Properties | Where-Object {
                        $_.Name -match "(?i)(pass|pwd|cred|secret|token|auth)" -and
                        $_.Value -is [byte[]] -and $_.Value.Length -gt 4
                    }
                    foreach ($p in $allPropNames) {
                        $dec = Unprotect-DpapiBlob -EncryptedBytes $p.Value
                        if ($dec -and $dec.Length -gt 2 -and $dec.Length -lt 200 -and $dec -notmatch '[\x00-\x08]') {
                            $password = $dec; $pwSource = "DPAPI ($($p.Name))"; break
                        }
                    }
                }

                $server = if ($imapServer) { $imapServer } elseif ($pop3Server) { $pop3Server } else { $null }
                $port = if ($imapPort) { $imapPort } elseif ($pop3Port) { $pop3Port } else { $null }
                $protocol = if ($imapServer) { "IMAP" } elseif ($pop3Server) { "POP3" } else { "OAuth2/Exchange" }
                $user = if ($imapUser) { $imapUser } elseif ($pop3User) { $pop3User } else { $email }

                $pwStatus = if ($password) { "GEFUNDEN" } else { "nicht gespeichert (OAuth2)" }
                $color = if ($password) { "Green" } else { "Yellow" }
                Write-Host "  $email - PW: $pwStatus" -ForegroundColor $color

                $accounts += [PSCustomObject]@{
                    DisplayName = if ($displayName) { $displayName } else { $email }
                    Email       = $email
                    Protocol    = $protocol
                    Server      = $server
                    Port        = $port
                    SmtpServer  = $smtpServer
                    SmtpPort    = $smtpPort
                    Username    = $user
                    Password    = $password
                    PwSource    = $pwSource
                }
            }
        }
    }

    if ($accounts.Count -eq 0) {
        Write-Host "  Keine Profile gefunden" -ForegroundColor DarkGray
    }
    return $accounts
}

# ============================================================================
# Quelle 2: Windows Credential Manager
# ============================================================================

function Get-AllCredentialManagerEntries {
    param([switch]$ShowAll)

    Write-Host "`n[2/3] Windows Credential Manager..." -ForegroundColor Cyan

    $results = @()

    try {
        $sig = @'
[DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern bool CredEnumerate(string filter, uint flags, out int count, out IntPtr credentials);

[DllImport("advapi32.dll")]
public static extern void CredFree(IntPtr buffer);

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct CREDENTIAL {
    public uint Flags;
    public uint Type;
    public string TargetName;
    public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
    public uint CredentialBlobSize;
    public IntPtr CredentialBlob;
    public uint Persist;
    public uint AttributeCount;
    public IntPtr Attributes;
    public string TargetAlias;
    public string UserName;
}
'@
        if (-not ([System.Management.Automation.PSTypeName]'Win32.CredManager').Type) {
            Add-Type -MemberDefinition $sig -Namespace "Win32" -Name "CredManager"
        }

        $count = 0; $pCreds = [IntPtr]::Zero
        if ([Win32.CredManager]::CredEnumerate($null, 0, [ref]$count, [ref]$pCreds)) {
            Write-Host "  $count Eintraege im Credential Manager" -ForegroundColor Gray

            $mailPatterns = @(
                "imap", "pop3", "smtp", "mail", "outlook", "office365",
                "live\.com", "hotmail", "gmail", "google", "gmx", "web\.de",
                "t-online", "proton", "posteo", "mailbox\.org", "icloud",
                "apple", "yahoo", "aol", "ionos", "1und1", "strato",
                "MicrosoftOffice", "WindowsLive", "freenet"
            )
            $pattern = ($mailPatterns -join "|")

            for ($i = 0; $i -lt $count; $i++) {
                $ptr = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($pCreds, $i * [IntPtr]::Size)
                $cred = [System.Runtime.InteropServices.Marshal]::PtrToStructure($ptr, [type][Win32.CredManager+CREDENTIAL])

                $isRelevant = $ShowAll -or ($cred.TargetName -match "(?i)($pattern)")

                if ($isRelevant) {
                    $password = $null
                    if ($cred.CredentialBlobSize -gt 0 -and $cred.CredentialBlob -ne [IntPtr]::Zero) {
                        $bytes = New-Object byte[] $cred.CredentialBlobSize
                        [System.Runtime.InteropServices.Marshal]::Copy($cred.CredentialBlob, $bytes, 0, $cred.CredentialBlobSize)

                        $password = [System.Text.Encoding]::Unicode.GetString($bytes).TrimEnd("`0")
                        if ($password -match '[\x00-\x08\x0E-\x1F]' -or [string]::IsNullOrWhiteSpace($password)) {
                            $password = [System.Text.Encoding]::UTF8.GetString($bytes).TrimEnd("`0")
                        }
                        if ($password -match '[\x00-\x08\x0E-\x1F]') {
                            $password = "[binary: " + ($bytes | ForEach-Object { $_.ToString("X2") }) -join "" + "]"
                        }
                    }

                    $results += [PSCustomObject]@{
                        Target   = $cred.TargetName
                        Type     = switch ($cred.Type) { 1 {"Generic"} 2 {"DomainPassword"} 3 {"DomainCertificate"} 4 {"DomainVisible"} default {"Type$($cred.Type)"} }
                        Username = $cred.UserName
                        Password = $password
                        HasPw    = [bool]$password
                    }

                    $pwLabel = if ($password -and $password -notmatch "^\[binary") { "PW gefunden!" } elseif ($password) { "binary blob" } else { "kein PW" }
                    $color = if ($password -and $password -notmatch "^\[binary") { "Green" } else { "DarkGray" }
                    Write-Host "  $($cred.TargetName)" -ForegroundColor $color -NoNewline
                    Write-Host " -> $($cred.UserName) ($pwLabel)" -ForegroundColor $color
                }
            }
            [Win32.CredManager]::CredFree($pCreds)
        }
    }
    catch {
        Write-Warning "  Credential Manager API Fehler: $($_.Exception.Message)"
    }

    return $results
}

# ============================================================================
# Quelle 3: Proton Bridge Credentials
# ============================================================================

function Get-ProtonBridgeCredentials {
    Write-Host "`n[3/3] Proton Bridge..." -ForegroundColor Cyan

    $bridgePaths = @(
        "$env:LOCALAPPDATA\protonmail\bridge-v3",
        "$env:APPDATA\protonmail\bridge-v3",
        "$env:LOCALAPPDATA\protonmail\bridge",
        "$env:APPDATA\protonmail\bridge"
    )

    foreach ($basePath in $bridgePaths) {
        if (-not (Test-Path $basePath)) { continue }

        Write-Host "  Bridge-Verzeichnis: $basePath" -ForegroundColor Gray

        $prefsFiles = @(
            (Join-Path $basePath "prefs.json"),
            (Join-Path $basePath "vault.json")
        )

        foreach ($pf in $prefsFiles) {
            if (Test-Path $pf) {
                try {
                    $content = Get-Content $pf -Raw | ConvertFrom-Json
                    Write-Host "  Config: $pf" -ForegroundColor Gray

                    if ($content.Users) {
                        foreach ($user in $content.Users.PSObject.Properties) {
                            $u = $user.Value
                            $email = if ($u.Emails) { $u.Emails[0] } elseif ($u.Email) { $u.Email } else { $user.Name }
                            Write-Host "  Proton User: $email" -ForegroundColor Green
                        }
                    }
                } catch {
                    Write-Host "  Konnte $pf nicht lesen: $($_.Exception.Message)" -ForegroundColor DarkGray
                }
            }
        }
    }

    Write-Host ""
    Write-Host "  ================================================" -ForegroundColor Yellow
    Write-Host "  Proton Bridge IMAP-Zugangsdaten anzeigen:" -ForegroundColor Yellow
    Write-Host "  1. Proton Bridge oeffnen" -ForegroundColor Yellow
    Write-Host "  2. Auf das Konto klicken" -ForegroundColor Yellow
    Write-Host "  3. 'Mailbox configuration' anzeigen" -ForegroundColor Yellow
    Write-Host "  4. IMAP: 127.0.0.1:1143 (STARTTLS)" -ForegroundColor Yellow
    Write-Host "  5. Username + Bridge Password werden angezeigt" -ForegroundColor Yellow
    Write-Host "  ================================================" -ForegroundColor Yellow
}

# ============================================================================
# Hauptprogramm
# ============================================================================

Write-Host "============================================================" -ForegroundColor White
Write-Host " Outlook Credential Export v2" -ForegroundColor White
Write-Host " Findet gespeicherte Mail-Passwoerter" -ForegroundColor Gray
Write-Host "============================================================" -ForegroundColor White
Write-Host ""
Write-Host " WICHTIG: Als normaler User ausfuehren (NICHT als Admin)!" -ForegroundColor Yellow

$registryAccounts = Get-OutlookRegistryAccounts
$credEntries = Get-AllCredentialManagerEntries -ShowAll:$DumpAllCredentials
Get-ProtonBridgeCredentials

# ============================================================================
# Zusammenfuehren und Anleitung pro Konto
# ============================================================================

Write-Host "`n" -NoNewline
Write-Host "============================================================" -ForegroundColor White
Write-Host " ERGEBNIS: Kontenliste mit Anleitung" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White

$allAccounts = @()

foreach ($acc in $registryAccounts) {
    $domain = ($acc.Email -split "@")[1].ToLower()
    $provider = $ImapProviders[$domain]

    $credPw = $null
    foreach ($cred in $credEntries) {
        if (-not $cred.Password -or $cred.Password -match "^\[binary") { continue }
        $target = $cred.Target.ToLower()
        $emailLc = $acc.Email.ToLower()
        $userLc = if ($cred.Username) { $cred.Username.ToLower() } else { "" }

        if ($target -match [regex]::Escape($emailLc) -or
            $userLc -eq $emailLc -or
            ($acc.Server -and $target -match [regex]::Escape($acc.Server.ToLower()))) {
            $credPw = $cred.Password
            break
        }
    }

    $finalPw = if ($acc.Password) { $acc.Password } elseif ($credPw) { $credPw } else { $null }
    $finalPwSource = if ($acc.Password) { $acc.PwSource } elseif ($credPw) { "CredentialManager" } else { $null }

    $imapHost = $acc.Server
    $imapPort = $acc.Port
    if (-not $imapHost -and $provider) {
        $imapHost = $provider.Host
        $imapPort = $provider.Port
    }
    if (-not $imapHost) {
        $imapHost = "imap.$domain"
        $imapPort = 993
    }

    $howToGetPw = switch -Regex ($domain) {
        "gmail\.com|googlemail\.com" {
            "Google App Password erstellen:`n" +
            "  1. https://myaccount.google.com/apppasswords`n" +
            "  2. 'Mail' als App, 'Windows Computer' als Geraet`n" +
            "  3. Generiertes 16-Zeichen-Passwort verwenden"
        }
        "icloud\.com|me\.com" {
            "Apple App Password erstellen:`n" +
            "  1. https://appleid.apple.com -> Anmelden`n" +
            "  2. Sicherheit -> App-spezifische Passwoerter`n" +
            "  3. Passwort generieren lassen"
        }
        "protonmail\.com|proton\.me" {
            "Proton Bridge IMAP-Passwort:`n" +
            "  1. Proton Bridge App oeffnen`n" +
            "  2. Konto anklicken -> 'Mailbox configuration'`n" +
            "  3. Bridge-Passwort kopieren`n" +
            "  IMAP: 127.0.0.1:1143 (STARTTLS, allowInsecureCert=true)"
        }
        "outlook\.com|hotmail|live\." {
            "Microsoft App Password erstellen:`n" +
            "  1. https://account.live.com/proofs/AppPassword`n" +
            "  2. (2FA muss aktiviert sein)`n" +
            "  3. Generiertes Passwort verwenden"
        }
        default {
            if ($provider -and $provider.Note) { $provider.Note }
            else { "Normales E-Mail-Passwort verwenden oder beim Provider nachschauen" }
        }
    }

    Write-Host "`n  ============================================" -ForegroundColor Cyan
    Write-Host "  $($acc.Email)" -ForegroundColor Cyan
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "  Name:       $($acc.DisplayName)"
    Write-Host "  Protokoll:  $($acc.Protocol)"
    Write-Host "  IMAP:       ${imapHost}:${imapPort}"
    if ($acc.SmtpServer) { Write-Host "  SMTP:       $($acc.SmtpServer):$($acc.SmtpPort)" }
    Write-Host "  Username:   $($acc.Username)"

    if ($finalPw) {
        Write-Host "  Passwort:   ****" -ForegroundColor Green
        Write-Host "  Quelle:     $finalPwSource" -ForegroundColor Green
    }
    else {
        Write-Host "  Passwort:   << nicht lokal gespeichert (OAuth2) >>" -ForegroundColor Red
        Write-Host ""
        Write-Host "  So kommst du ans Passwort:" -ForegroundColor Yellow
        foreach ($line in ($howToGetPw -split "`n")) {
            Write-Host "  $line" -ForegroundColor Yellow
        }
    }

    $allAccounts += [ordered]@{
        Email             = $acc.Email
        DisplayName       = $acc.DisplayName
        Protocol          = $acc.Protocol
        ImapHost          = $imapHost
        ImapPort          = $imapPort
        ImapSecure        = ($domain -ne "protonmail.com" -and $domain -ne "proton.me")
        AllowInsecureCert = ($domain -eq "protonmail.com" -or $domain -eq "proton.me")
        SmtpServer        = $acc.SmtpServer
        SmtpPort          = $acc.SmtpPort
        Username          = $acc.Username
        Password          = $finalPw
        PasswordSource    = $finalPwSource
        PasswordHelp      = if (-not $finalPw) { $howToGetPw -replace "`n", " | " } else { $null }
    }
}

# ============================================================================
# JSON Export
# ============================================================================

$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
if (-not $OutputFile) {
    $OutputFile = Join-Path $PSScriptRoot "outlook-credentials_$timestamp.json"
}

$exportData = [ordered]@{
    ExportDate        = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    Computer          = $env:COMPUTERNAME
    User              = $env:USERNAME
    Accounts          = $allAccounts
    CredentialManager = ($credEntries | Where-Object { $_.Password -and $_.Password -notmatch "^\[binary" } |
                         ForEach-Object { [ordered]@{ Target=$_.Target; Username=$_.Username; Password="****" } })
    HowToImport       = @(
        "1. JSON-Datei auf den Server kopieren (SCP/USB)",
        "2. OpenArchiver oeffnen: http://YOUR_SERVER_IP:3000",
        "3. Ingestion Sources -> New -> Generic IMAP",
        "4. Daten aus dieser JSON eintragen",
        "5. Fuer PST: Ingestion Sources -> New -> PST Import"
    )
}

$exportData | ConvertTo-Json -Depth 4 | Set-Content -Path $OutputFile -Encoding UTF8

Write-Host "`n============================================================" -ForegroundColor White
Write-Host " Export: $OutputFile" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor White
Write-Host ""
Write-Host " WARNUNG: Datei kann Klartext-Passwoerter enthalten!" -ForegroundColor Red
Write-Host " Nach Verwendung sicher loeschen!" -ForegroundColor Red
Write-Host ""
Write-Host " Naechste Schritte:" -ForegroundColor White
Write-Host "   1. Fehlende Passwoerter erstellen (siehe Anleitungen oben)" -ForegroundColor Yellow
Write-Host "   2. In die JSON-Datei eintragen" -ForegroundColor Yellow
Write-Host "   3. JSON auf den Server kopieren" -ForegroundColor Yellow
Write-Host "   4. OpenArchiver: http://YOUR_SERVER_IP:3000" -ForegroundColor Yellow
Write-Host ""
Write-Host " TIPP: Mit -DumpAllCredentials alle Credential Manager" -ForegroundColor Gray
Write-Host "       Eintraege anzeigen (nicht nur Mail-bezogene)" -ForegroundColor Gray

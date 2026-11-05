# LeakWatch - DNS leak test for Windows (PowerShell 5.1+, no extra software).
# Resolves unique names through the Windows resolver, then asks bash.ws which
# DNS servers made those lookups. Writes leakwatch.log and status.json to
# %LOCALAPPDATA%\LeakWatch (status.json is read by the tray app).
# -Quiet : no notifications/sounds and no waiting for the network.
param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
$Dir        = Join-Path $env:LOCALAPPDATA 'LeakWatch'
$ConfigFile = Join-Path $Dir 'config.json'
$LogFile    = Join-Path $Dir 'leakwatch.log'
$StatusFile = Join-Path $Dir 'status.json'
$Api        = 'https://bash.ws'
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---- settings (defaults, overridden by config.json) ----
$cfg = @{
    allowedCountries = @()
    alertWords       = @()
    leakSound        = 'C:\Windows\Media\Windows Exclamation.wav'
    criticalSound    = 'C:\Windows\Media\Windows Critical Stop.wav'
    criticalRepeat   = 3
}
if (Test-Path $ConfigFile) {
    $c = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    foreach ($k in @($cfg.Keys)) { if ($null -ne $c.$k) { $cfg[$k] = $c.$k } }
}
$allowed = @($cfg.allowedCountries | Where-Object { "$_".Trim() } | ForEach-Object { "$_".Trim() })
$words   = @($cfg.alertWords | ForEach-Object { "$_".Trim().ToLower() } | Where-Object { $_ })

function Ts { (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
function Add-Log([string]$text) { Add-Content -Path $LogFile -Value $text -Encoding UTF8 }

function Save-Status([string]$status, [string]$message, $data, [string[]]$flagged) {
    $ip = $null; $dns = @()
    if ($data) {
        $ip  = @($data | Where-Object { $_.type -eq 'ip' }) | Select-Object -First 1
        $dns = @($data | Where-Object { $_.type -eq 'dns' })
    }
    $obj = [ordered]@{
        time    = (Ts)
        epoch   = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        status  = $status
        message = $message
        ip      = $ip
        dns     = $dns
        flagged = @($flagged)
    }
    $tmp = "$StatusFile.tmp"
    ConvertTo-Json -InputObject $obj -Depth 5 | Set-Content -Path $tmp -Encoding UTF8
    Move-Item -Path $tmp -Destination $StatusFile -Force
}

function Fail([string]$msg) {
    Add-Log "[$(Ts)] ERROR: $msg"
    Save-Status 'ERROR' $msg $null @()
    exit 1
}

function Show-Toast([string]$title, [string]$text) {
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $t = [Security.SecurityElement]::Escape($title)
        $m = [Security.SecurityElement]::Escape($text)
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml("<toast><visual><binding template='ToastGeneric'><text>$t</text><text>$m</text></binding></visual><audio silent='true'/></toast>")
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
    } catch { }
}

function Play-Sound([string]$path, [int]$times) {
    if (-not (Test-Path $path)) { return }
    try {
        $p = New-Object System.Media.SoundPlayer $path
        for ($i = 0; $i -lt $times; $i++) { $p.PlaySync() }
    } catch { }
}

function Show-Popup([string]$title, [string]$text) {
    # Separate hidden process so this script can finish; the box stays until closed.
    $cmd = "Add-Type -AssemblyName System.Windows.Forms; " +
           "[System.Windows.Forms.MessageBox]::Show('" + $text.Replace("'", "''") + "', '" + $title.Replace("'", "''") + "', 'OK', 'Error', 'Button1', 'DefaultDesktopOnly') | Out-Null"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile', '-EncodedCommand', $enc
}

# ---- wait for network/VPN after login or wake (up to ~2 min) ----
if (-not $Quiet) {
    for ($i = 0; $i -lt 12; $i++) {
        try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 "$Api/id" | Out-Null; break } catch { Start-Sleep 10 }
    }
}

# ---- the test ----
try { $id = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 15 "$Api/id").Content.Trim() }
catch { Fail 'cannot reach bash.ws (offline?)' }

foreach ($n in 1..10) {
    try { [void][System.Net.Dns]::GetHostAddresses("$n.$id.bash.ws") } catch { }   # failures are expected
}

try {
    $raw  = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 15 "$Api/dnsleak/test/$($id)?json").Content
    $data = ConvertFrom-Json $raw
} catch { Fail 'result fetch failed' }

# ---- evaluate ----
$bad = @(); $crit = @()
foreach ($e in $data) {
    if ($e.type -ne 'ip' -and $e.type -ne 'dns') { continue }
    $line = '{0} {1} [{2}] {3}' -f $e.type.ToUpper(), $e.ip, $e.country_name, $e.asn
    $text = ("$($e.country_name) $($e.asn) $($e.org)").ToLower()
    $cc   = "$($e.country)".ToLower()
    $isCrit = $false
    foreach ($w in $words) {
        if ($w.Length -eq 2) { if ($cc -eq $w) { $isCrit = $true } }
        elseif ($text.Contains($w)) { $isCrit = $true }
    }
    if ($isCrit) { $crit += $line }
    if ($allowed.Count -gt 0 -and ($allowed -notcontains "$($e.country_name)")) { $bad += $line }
}

$ipE  = @($data | Where-Object { $_.type -eq 'ip' }) | Select-Object -First 1
$dnsE = @($data | Where-Object { $_.type -eq 'dns' })
$out = @("===== $(Ts) =====")
if ($ipE) { $out += 'Your IP:   {0}  [{1}] {2}' -f $ipE.ip, $ipE.country_name, $ipE.asn }
$out += "DNS servers seen: $($dnsE.Count)"
foreach ($d in $dnsE) { $out += '  - {0}  [{1}] {2}' -f $d.ip, $d.country_name, $d.asn }
if ($crit.Count) { $out += 'STATUS: CRITICAL - alert location detected:'; $out += $crit | ForEach-Object { "  !!! $_" } }
elseif ($bad.Count) { $out += 'STATUS: LEAK - unwanted location:'; $out += $bad | ForEach-Object { "  ! $_" } }
else { $out += 'STATUS: OK (all locations allowed)' }
$out += ''
Add-Log ($out -join "`r`n")
$out | Write-Output

if ($crit.Count)    { Save-Status 'CRITICAL' 'Alert location detected' $data $crit }
elseif ($bad.Count) { Save-Status 'LEAK' 'Unwanted location' $data $bad }
else                { Save-Status 'OK' 'All locations allowed' $data @() }

# ---- alerts ----
if (-not $Quiet) {
    if ($crit.Count) {
        $msg = ($crit | Select-Object -First 3) -join "`n"
        Show-Toast 'LeakWatch: real location exposed' $msg
        Show-Popup 'LeakWatch: real location exposed' $msg
        Play-Sound $cfg.criticalSound ([int]$cfg.criticalRepeat)
    } elseif ($bad.Count) {
        Show-Toast 'LeakWatch: DNS leak detected' (($bad | Select-Object -First 3) -join "`n")
        Play-Sound $cfg.leakSound 1
    }
}

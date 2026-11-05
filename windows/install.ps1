# LeakWatch installer for Windows (no admin rights needed).
# Copies files to %LOCALAPPDATA%\LeakWatch, asks for your settings,
# and starts the tray app at every login.
$ErrorActionPreference = 'Stop'
$Src = Split-Path -Parent $MyInvocation.MyCommand.Path
$Dir = Join-Path $env:LOCALAPPDATA 'LeakWatch'
$ConfigFile = Join-Path $Dir 'config.json'

function Bold([string]$t) { Write-Host ''; Write-Host $t -ForegroundColor Cyan }
function To-List([string]$s) { @($s -split ',' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ }) }

# Stop a running tray app before replacing files
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like '*LeakWatchTray.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
foreach ($f in 'leakwatch.ps1', 'LeakWatchTray.ps1', 'run-hidden.vbs', 'uninstall.ps1') {
    Copy-Item (Join-Path $Src $f) (Join-Path $Dir $f) -Force
}
Get-ChildItem $Dir -File | Unblock-File -ErrorAction SilentlyContinue

# ---- settings ----
if (Test-Path $ConfigFile) {
    Bold "Keeping your existing settings: $ConfigFile"
} else {
    Bold 'Step 1. Connect your VPN now, then press Enter.'
    [void](Read-Host)
    Write-Host 'Running a first test (takes a few seconds)...'
    try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dir 'leakwatch.ps1') -Quiet | Out-Null } catch { }
    $seen = ''
    try {
        $s = Get-Content (Join-Path $Dir 'status.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $names = @()
        if ($s.ip) { $names += $s.ip.country_name }
        foreach ($d in @($s.dns)) { if ($d) { $names += $d.country_name } }
        $seen = (@($names | Where-Object { $_ } | Sort-Object -Unique)) -join ', '
    } catch { }

    Bold 'Step 2. Allowed countries (where your VPN servers are).'
    if ($seen) {
        Write-Host "Countries seen right now: $seen"
        $ans = Read-Host 'Press Enter to allow exactly these, or type your own comma-separated list'
        $allowed = if ($ans) { $ans } else { $seen }
    } else {
        Write-Host 'Could not run the test (offline?).'
        $allowed = Read-Host 'Type allowed countries, comma-separated (e.g. Netherlands, Sweden), or leave empty'
    }
    Write-Host "Names must match how bash.ws writes them (e.g. 'United States', 'Russian Federation')."

    Bold 'Step 3. Your real country.'
    Write-Host 'If it EVER shows up in a test, LeakWatch raises a red alert with a pop-up and sound.'
    $home_ = Read-Host 'Country name (e.g. Russia, Iran, China, Turkey) or leave empty'
    $extra = Read-Host 'Optional extra alert words - cities or ISP names, comma-separated'

    $cfg = [ordered]@{
        '_help'          = 'allowedCountries: VPN/DNS countries that are OK (exact bash.ws names; empty = skip). alertWords: words meaning your real location is exposed (2-letter word = country code). Sounds: any .wav file.'
        allowedCountries = To-List $allowed
        alertWords       = To-List "$home_, $extra"
        leakSound        = 'C:\Windows\Media\Windows Exclamation.wav'
        criticalSound    = 'C:\Windows\Media\Windows Critical Stop.wav'
        criticalRepeat   = 3
    }
    ConvertTo-Json -InputObject $cfg -Depth 3 | Set-Content -Path $ConfigFile -Encoding UTF8
    Bold "Saved settings to $ConfigFile"
}

# ---- start at login (current user) + start now ----
$vbs = Join-Path $Dir 'run-hidden.vbs'
$cmd = "wscript.exe `"$vbs`" LeakWatchTray.ps1"
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'LeakWatch' -Value $cmd -PropertyType String -Force | Out-Null
Start-Process wscript.exe -ArgumentList "`"$vbs`"", 'LeakWatchTray.ps1'

Bold 'Done! LeakWatch is running.'
Write-Host '  - Tray icon near the clock (it may be in the hidden icons arrow - drag it out to keep it visible)'
Write-Host '  - Desktop widget: top-right, drag to move'
Write-Host '  - Tests run at login and every hour; alerts only when something is wrong'
Write-Host "  - Settings: $ConfigFile"
Write-Host "  - Uninstall: run uninstall.cmd (or $Dir\uninstall.ps1)"
Write-Host ''
Read-Host 'Press Enter to close'

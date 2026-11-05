# LeakWatch installer for Windows (no admin rights needed).
# Copies files to %LOCALAPPDATA%\LeakWatch, asks for your settings,
# and starts the tray app at every login.
# Messages are shown in Russian first, then in English.
# NOTE: this file must stay UTF-8 *with BOM* so Windows PowerShell 5.1 reads Cyrillic correctly.
$ErrorActionPreference = 'Stop'
$Src = Split-Path -Parent $MyInvocation.MyCommand.Path
$Dir = Join-Path $env:LOCALAPPDATA 'LeakWatch'
$ConfigFile = Join-Path $Dir 'config.json'

function Title([string]$ru, [string]$en) { Write-Host ''; Write-Host $ru -ForegroundColor Cyan; Write-Host $en -ForegroundColor DarkGray }
function Say([string]$ru, [string]$en)   { Write-Host $ru; Write-Host $en -ForegroundColor DarkGray }
function Ask([string]$ru, [string]$en)   { Say $ru $en; return (Read-Host '>') }
function To-List([string]$s) { @($s -split ',' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ }) }

Title 'LeakWatch — установка' 'LeakWatch installer'

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
    Title "Оставляю твои прежние настройки: $ConfigFile" "Keeping your existing settings: $ConfigFile"
} else {
    Title 'Шаг 1. Подключи VPN и нажми Enter.' 'Step 1. Connect your VPN now, then press Enter.'
    [void](Read-Host '>')
    Say 'Провожу первую проверку (несколько секунд)...' 'Running a first test (takes a few seconds)...'
    try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dir 'leakwatch.ps1') -Quiet | Out-Null } catch { }
    $seen = ''
    try {
        $s = Get-Content (Join-Path $Dir 'status.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $names = @()
        if ($s.ip) { $names += $s.ip.country_name }
        foreach ($d in @($s.dns)) { if ($d) { $names += $d.country_name } }
        $seen = (@($names | Where-Object { $_ } | Sort-Object -Unique)) -join ', '
    } catch { }

    Title 'Шаг 2. Разрешённые страны (где находятся серверы твоего VPN).' 'Step 2. Allowed countries (where your VPN servers are).'
    Say "Названия — по-английски, как их пишет bash.ws (например, 'United States', 'Russian Federation')." "Names must match how bash.ws writes them (e.g. 'United States', 'Russian Federation')."
    if ($seen) {
        Say "Сейчас видны страны: $seen" "Countries seen right now: $seen"
        $ans = Ask 'Нажми Enter, чтобы разрешить именно их, или впиши свой список через запятую:' 'Press Enter to allow exactly these, or type your own comma-separated list:'
        $allowed = if ($ans) { $ans } else { $seen }
    } else {
        Say 'Не удалось провести проверку (нет интернета?).' 'Could not run the test (offline?).'
        $allowed = Ask 'Впиши разрешённые страны через запятую (например: Netherlands, Sweden) или оставь пустым:' 'Type allowed countries, comma-separated (e.g. Netherlands, Sweden), or leave empty:'
    }

    Title 'Шаг 3. Твоя реальная страна.' 'Step 3. Your real country.'
    Say 'Если она хоть раз появится в проверке, LeakWatch поднимет красную тревогу: окно и звук.' 'If it EVER shows up in a test, LeakWatch raises a red alert with a pop-up and sound.'
    $home_ = Ask 'Название страны латиницей (например: Russia, Iran, China, Turkey) или оставь пустым:' 'Country name (e.g. Russia, Iran, China, Turkey) or leave empty:'
    $extra = Ask 'Необязательно: другие слова-тревоги — города или провайдеры, через запятую:' 'Optional extra alert words - cities or ISP names, comma-separated:'

    $cfg = [ordered]@{
        '_help'          = 'allowedCountries: VPN/DNS countries that are OK (exact bash.ws names; empty = skip). alertWords: words meaning your real location is exposed (2-letter word = country code). Sounds: any .wav file.'
        allowedCountries = To-List $allowed
        alertWords       = To-List "$home_, $extra"
        leakSound        = 'C:\Windows\Media\Windows Exclamation.wav'
        criticalSound    = 'C:\Windows\Media\Windows Critical Stop.wav'
        criticalRepeat   = 3
    }
    ConvertTo-Json -InputObject $cfg -Depth 3 | Set-Content -Path $ConfigFile -Encoding UTF8
    Title "Настройки сохранены: $ConfigFile" "Saved settings to $ConfigFile"
}

# ---- start at login (current user) + start now ----
$vbs = Join-Path $Dir 'run-hidden.vbs'
$cmd = "wscript.exe `"$vbs`" LeakWatchTray.ps1"
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'LeakWatch' -Value $cmd -PropertyType String -Force | Out-Null
Start-Process wscript.exe -ArgumentList "`"$vbs`"", 'LeakWatchTray.ps1'

Title 'Готово! LeakWatch работает.' 'Done! LeakWatch is running.'
Say '  - Значок в трее у часов (может быть среди скрытых значков ^ — перетащи его к часам)' '  - Tray icon near the clock (it may be in the hidden icons arrow - drag it out to keep it visible)'
Say '  - Виджет на рабочем столе: справа вверху, можно перетащить' '  - Desktop widget: top-right, drag to move'
Say '  - Проверка при входе и каждый час; оповещения — только если что-то не так' '  - Tests run at login and every hour; alerts only when something is wrong'
Say "  - Настройки: $ConfigFile" "  - Settings: $ConfigFile"
Say "  - Удаление: uninstall.cmd (или $Dir\uninstall.ps1)" "  - Uninstall: run uninstall.cmd (or $Dir\uninstall.ps1)"
Write-Host ''
[void](Ask 'Нажми Enter, чтобы закрыть окно.' 'Press Enter to close.')

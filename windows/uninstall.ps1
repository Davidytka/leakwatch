# Removes LeakWatch from Windows. Messages: Russian first, then English.
# NOTE: this file must stay UTF-8 *with BOM* so Windows PowerShell 5.1 reads Cyrillic correctly.
$Dir = Join-Path $env:LOCALAPPDATA 'LeakWatch'
function Say([string]$ru, [string]$en) { Write-Host $ru; Write-Host $en -ForegroundColor DarkGray }

Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like '*LeakWatchTray.ps1*' -or $_.CommandLine -like '*leakwatch.ps1*' } |
    Where-Object { $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'LeakWatch' -ErrorAction SilentlyContinue

Say 'Удалить также настройки и журнал? [y/N]' 'Also delete settings and log? [y/N]'
$a = Read-Host '>'
if ($a -match '^(y|д)') {
    Remove-Item $Dir -Recurse -Force -ErrorAction SilentlyContinue
    Say 'Настройки и журнал удалены.' 'Settings and log deleted.'
} else {
    foreach ($f in 'leakwatch.ps1', 'LeakWatchTray.ps1', 'run-hidden.vbs', 'widget.json', 'status.json') {
        Remove-Item (Join-Path $Dir $f) -Force -ErrorAction SilentlyContinue
    }
}
Say 'LeakWatch удалён.' 'LeakWatch removed.'
[void](Read-Host '>')

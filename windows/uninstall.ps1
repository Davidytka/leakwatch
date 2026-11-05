# Removes LeakWatch from Windows.
$Dir = Join-Path $env:LOCALAPPDATA 'LeakWatch'

Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like '*LeakWatchTray.ps1*' -or $_.CommandLine -like '*leakwatch.ps1*' } |
    Where-Object { $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'LeakWatch' -ErrorAction SilentlyContinue

$a = Read-Host 'Also delete settings and log? [y/N]'
if ($a -match '^[yY]') {
    Remove-Item $Dir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host 'Settings and log deleted.'
} else {
    foreach ($f in 'leakwatch.ps1', 'LeakWatchTray.ps1', 'run-hidden.vbs', 'widget.json', 'status.json') {
        Remove-Item (Join-Path $Dir $f) -Force -ErrorAction SilentlyContinue
    }
}
Write-Host 'LeakWatch removed.'
Read-Host 'Press Enter to close'

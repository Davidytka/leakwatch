' Runs a LeakWatch PowerShell script with no console window.
' Usage: wscript.exe run-hidden.vbs <script.ps1>
Set sh = CreateObject("WScript.Shell")
dir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\" & WScript.Arguments(0) & """", 0, False

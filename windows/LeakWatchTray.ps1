# LeakWatch tray icon + desktop widget for Windows (PowerShell 5.1, WinForms).
# Shows the latest result from status.json and runs leakwatch.ps1 every hour.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---- single instance ----
$created = $false
$script:mutex = New-Object System.Threading.Mutex($true, 'Local\LeakWatchTray', [ref]$created)
if (-not $created) { exit }

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class LWNative {
    [DllImport("user32.dll")] public static extern bool ReleaseCapture();
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int msg, int w, int l);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
}
"@

$Dir          = Join-Path $env:LOCALAPPDATA 'LeakWatch'
$StatusFile   = Join-Path $Dir 'status.json'
$LogFile      = Join-Path $Dir 'leakwatch.log'
$ConfigFile   = Join-Path $Dir 'config.json'
$WidgetFile   = Join-Path $Dir 'widget.json'
$TestScript   = Join-Path $Dir 'leakwatch.ps1'
$StaleAfter   = 75 * 60      # seconds without a test => "No recent test"
$TestEvery    = 60 * 60      # run a test every hour
$RetryAfter   = 5 * 60       # after a failed attempt, wait before retrying

$script:testing     = $false
$script:proc        = $null
$script:lastAttempt = 0

# ---- states ----
$States = @{
    ok       = @{ title = 'No leaks';                color = [Drawing.Color]::FromArgb(52, 199, 89);   mark = 'check' }
    leak     = @{ title = 'Leak: unwanted location'; color = [Drawing.Color]::FromArgb(255, 149, 0);   mark = 'cross' }
    critical = @{ title = 'Real location exposed';   color = [Drawing.Color]::FromArgb(255, 59, 48);   mark = 'cross' }
    error    = @{ title = 'Test failed';             color = [Drawing.Color]::FromArgb(255, 149, 0);   mark = 'cross' }
    testing  = @{ title = 'Testing...';              color = [Drawing.Color]::FromArgb(0, 122, 255);   mark = 'sync' }
    stale    = @{ title = 'No recent test';          color = [Drawing.Color]::FromArgb(142, 142, 147); mark = 'clock' }
    unknown  = @{ title = 'No data yet';             color = [Drawing.Color]::FromArgb(142, 142, 147); mark = 'clock' }
}

function Now { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

function New-StateBitmap([string]$name, [int]$size) {
    $st  = $States[$name]
    $bmp = New-Object Drawing.Bitmap $size, $size
    $g   = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $brush = New-Object Drawing.SolidBrush $st.color
    $g.FillEllipse($brush, 0, 0, $size - 1, $size - 1)
    $pen = New-Object Drawing.Pen ([Drawing.Color]::White), ([Math]::Max(1.5, $size / 8))
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
    $s = $size
    switch ($st.mark) {
        'check' { $g.DrawLines($pen, [Drawing.PointF[]]@(
                    (New-Object Drawing.PointF ($s * 0.28), ($s * 0.52)),
                    (New-Object Drawing.PointF ($s * 0.44), ($s * 0.68)),
                    (New-Object Drawing.PointF ($s * 0.73), ($s * 0.35)))) }
        'cross' { $g.DrawLine($pen, $s * 0.33, $s * 0.33, $s * 0.67, $s * 0.67)
                  $g.DrawLine($pen, $s * 0.67, $s * 0.33, $s * 0.33, $s * 0.67) }
        'clock' { $g.DrawLine($pen, $s * 0.5, $s * 0.5, $s * 0.5, $s * 0.25)
                  $g.DrawLine($pen, $s * 0.5, $s * 0.5, $s * 0.7, $s * 0.5) }
        'sync'  { $g.DrawArc($pen, $s * 0.27, $s * 0.27, $s * 0.46, $s * 0.46, 30, 280) }
    }
    $pen.Dispose(); $brush.Dispose(); $g.Dispose()
    return $bmp
}

# Pre-render icons once (tray icon, menu images, widget image)
$Icons = @{}; $MenuImg = @{}; $WidgetImg = @{}
foreach ($k in $States.Keys) {
    $Icons[$k]     = [Drawing.Icon]::FromHandle((New-StateBitmap $k 32).GetHicon())
    $MenuImg[$k]   = New-StateBitmap $k 16
    $WidgetImg[$k] = New-StateBitmap $k 26
}

# ---- data ----
function Load-Status {
    if (-not (Test-Path $StatusFile)) { return $null }
    try { return Get-Content $StatusFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
}

function Get-StateName($s) {
    if ($script:testing) { return 'testing' }
    if (-not $s) { return 'unknown' }
    switch ($s.status) { 'CRITICAL' { return 'critical' } 'LEAK' { return 'leak' } 'ERROR' { return 'error' } }
    if ((Now) - [long]$s.epoch -gt $StaleAfter) { return 'stale' }
    return 'ok'
}

function Format-Ago([long]$epoch) {
    $m = [int](((Now) - $epoch) / 60)
    function P($n, $w) { if ($n -eq 1) { "1 $w ago" } else { "$n ${w}s ago" } }
    if ($m -lt 1) { return 'just now' }
    if ($m -lt 60) { return (P $m 'minute') }
    if ($m -lt 1440) { return (P ([int][Math]::Floor($m / 60)) 'hour') }
    return (P ([int][Math]::Floor($m / 1440)) 'day')
}

function Short($e) {
    $org = if ($e.org) { $e.org } elseif ($e.asn) { $e.asn } else { '' }
    if ($org) { "$($e.country_name) - $org" } else { "$($e.country_name)" }
}

function Get-Details($s) {
    if (-not $s) { return @('Waiting for the first test.') }
    $lines = @()
    if ($s.status -eq 'ERROR') { $lines += $s.message }
    if ($s.ip) { $lines += 'IP:  ' + (Short $s.ip) }
    $counts = [ordered]@{}
    foreach ($d in @($s.dns)) { if ($d) { $k = Short $d; if ($counts.Contains($k)) { $counts[$k]++ } else { $counts[$k] = 1 } } }
    foreach ($k in $counts.Keys) { $lines += 'DNS: ' + $k + $(if ($counts[$k] -gt 1) { "  x$($counts[$k])" } else { '' }) }
    $fl = @($s.flagged | Where-Object { $_ })
    if ($fl.Count) { $lines += 'Flagged:'; $lines += $fl | ForEach-Object { "  $_" } }
    return $lines
}

function Get-History([int]$n) {
    if (-not (Test-Path $LogFile)) { return @() }
    $out = New-Object System.Collections.ArrayList
    $cur = $null
    foreach ($line in (Get-Content $LogFile -Encoding UTF8)) {
        if ($line.StartsWith('===== ')) { $cur = $line.Replace('=', '').Trim() }
        elseif ($line.StartsWith('STATUS: ') -and $cur) {
            [void]$out.Add([pscustomobject]@{ t = $cur; s = $line.Substring(8).Split(' ')[0] }); $cur = $null
        } elseif ($line.StartsWith('[') -and $line.Contains('ERROR') -and $line.IndexOf(']') -gt 0) {
            [void]$out.Add([pscustomobject]@{ t = $line.Substring(1, $line.IndexOf(']') - 1); s = 'ERROR' })
        }
    }
    $last = @($out | Select-Object -Last $n)
    [array]::Reverse($last)
    return $last
}

# ---- widget settings (position / visibility) ----
function Load-Widget {
    $w = @{ show = $true; x = $null; y = $null }
    if (Test-Path $WidgetFile) {
        try { $j = Get-Content $WidgetFile -Raw | ConvertFrom-Json; $w.show = [bool]$j.show; $w.x = $j.x; $w.y = $j.y } catch { }
    }
    return $w
}
function Save-Widget {
    $o = @{ show = $script:widget.show; x = $form.Left; y = $form.Top }
    ConvertTo-Json $o | Set-Content -Path $WidgetFile -Encoding UTF8
}
$script:widget = Load-Widget

# ---- running tests ----
function Start-Test {
    if ($script:testing) { return }
    $script:testing = $true
    $script:lastAttempt = Now
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$TestScript`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $script:proc = [Diagnostics.Process]::Start($psi)
    $procTimer.Start()
    Update-UI
}

# ---- desktop widget ----
$form = New-Object Windows.Forms.Form
$form.FormBorderStyle = 'None'
$form.ShowInTaskbar = $false
$form.StartPosition = 'Manual'
$form.BackColor = [Drawing.Color]::FromArgb(36, 36, 40)
$form.Opacity = 0.94
$form.Width = 300
$form.Text = 'LeakWatch'

$pic = New-Object Windows.Forms.PictureBox
$pic.Size = New-Object Drawing.Size 26, 26
$pic.Location = New-Object Drawing.Point 16, 14

$headline = New-Object Windows.Forms.Label
$headline.AutoSize = $false
$headline.Size = New-Object Drawing.Size 150, 26
$headline.Location = New-Object Drawing.Point 50, 14
$headline.TextAlign = 'MiddleLeft'
$headline.AutoEllipsis = $true
$headline.Font = New-Object Drawing.Font 'Segoe UI Semibold', 12
$headline.ForeColor = [Drawing.Color]::White

$btn = New-Object Windows.Forms.Button
$btn.Text = 'Test now'
$btn.Size = New-Object Drawing.Size 80, 26
$btn.Location = New-Object Drawing.Point 204, 14
$btn.FlatStyle = 'Flat'
$btn.FlatAppearance.BorderSize = 0
$btn.BackColor = [Drawing.Color]::FromArgb(64, 64, 70)
$btn.ForeColor = [Drawing.Color]::White
$btn.Font = New-Object Drawing.Font 'Segoe UI', 9
$btn.Cursor = 'Hand'
$btn.Add_Click({ Start-Test })

$sub = New-Object Windows.Forms.Label
$sub.AutoSize = $true
$sub.Location = New-Object Drawing.Point 16, 48
$sub.Font = New-Object Drawing.Font 'Segoe UI', 8.5
$sub.ForeColor = [Drawing.Color]::FromArgb(170, 170, 176)

$details = New-Object Windows.Forms.Label
$details.AutoSize = $true
$details.MaximumSize = New-Object Drawing.Size 268, 0
$details.Location = New-Object Drawing.Point 16, 70
$details.Font = New-Object Drawing.Font 'Segoe UI', 9
$details.ForeColor = [Drawing.Color]::FromArgb(230, 230, 235)

$form.Controls.AddRange(@($pic, $headline, $btn, $sub, $details))

# Drag the widget by any part except the button
$dragHandler = {
    param($s, $e)
    if ($e.Button -eq 'Left') {
        [void][LWNative]::ReleaseCapture()
        [void][LWNative]::SendMessage($form.Handle, 0xA1, 2, 0)   # WM_NCLBUTTONDOWN, HTCAPTION
        Save-Widget
    }
}
foreach ($c in @($form, $pic, $headline, $sub, $details)) { $c.Add_MouseDown($dragHandler) }

function Set-Rounded {
    $r = 16; $w = $form.Width; $h = $form.Height
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $r * 2, $r * 2, 180, 90)
    $path.AddArc($w - $r * 2, 0, $r * 2, $r * 2, 270, 90)
    $path.AddArc($w - $r * 2, $h - $r * 2, $r * 2, $r * 2, 0, 90)
    $path.AddArc(0, $h - $r * 2, $r * 2, $r * 2, 90, 90)
    $path.CloseFigure()
    $form.Region = New-Object Drawing.Region $path
}

# Keep the widget below normal windows (like a desktop widget)
function Send-ToBottom { [void][LWNative]::SetWindowPos($form.Handle, [IntPtr]1, 0, 0, 0, 0, 0x13) }  # HWND_BOTTOM; NOSIZE|NOMOVE|NOACTIVATE
$form.Add_Activated({ Send-ToBottom })

$wa = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
if ($null -ne $script:widget.x -and $null -ne $script:widget.y) {
    $form.Location = New-Object Drawing.Point ([int]$script:widget.x), ([int]$script:widget.y)
} else {
    $form.Location = New-Object Drawing.Point ($wa.Right - 320), ($wa.Top + 20)
}

# ---- tray icon ----
$tray = New-Object Windows.Forms.NotifyIcon
$tray.Visible = $true
$menu = New-Object Windows.Forms.ContextMenuStrip
$tray.ContextMenuStrip = $menu
$tray.Add_MouseUp({
    param($s, $e)
    if ($e.Button -eq 'Left') {
        $m = [Windows.Forms.NotifyIcon].GetMethod('ShowContextMenu', [Reflection.BindingFlags]'Instance,NonPublic')
        $m.Invoke($tray, $null)
    }
})

function Add-Info([string]$text, $img) {
    $i = $menu.Items.Add($text)
    $i.Enabled = $false
    if ($img) { $i.Image = $img }
    return $i
}

function Build-Menu {
    $s = Load-Status
    $name = Get-StateName $s
    $menu.Items.Clear()
    $h = Add-Info $States[$name].title $MenuImg[$name]
    $h.Font = New-Object Drawing.Font $menu.Font, ([Drawing.FontStyle]::Bold)
    if ($s) { [void](Add-Info ('Last test: ' + (Format-Ago ([long]$s.epoch))) $null) }
    foreach ($l in (Get-Details $s)) { [void](Add-Info $l $null) }
    [void]$menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    [void](Add-Info 'Recent tests:' $null)
    foreach ($r in (Get-History 6)) {
        $k = switch ($r.s) { 'OK' { 'ok' } 'CRITICAL' { 'critical' } default { 'leak' } }
        $t = if ($r.t.Length -ge 16) { $r.t.Substring(5, 11) } else { $r.t }
        [void](Add-Info "$t   $($r.s)" $MenuImg[$k])
    }
    [void]$menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    $run = $menu.Items.Add($(if ($script:testing) { 'Testing...' } else { 'Test now' }))
    $run.Enabled = -not $script:testing
    $run.Add_Click({ Start-Test })
    $menu.Items.Add('Open log').Add_Click({ if (Test-Path $LogFile) { Start-Process notepad.exe $LogFile } })
    $menu.Items.Add('Edit settings').Add_Click({ Start-Process notepad.exe $ConfigFile })
    $show = $menu.Items.Add('Show desktop widget')
    $show.Checked = $script:widget.show
    $show.Add_Click({ $script:widget.show = -not $script:widget.show; Save-Widget; Update-UI })
    [void]$menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    $menu.Items.Add('Quit LeakWatch').Add_Click({
        $tray.Visible = $false
        [Windows.Forms.Application]::Exit()
    })
}
$menu.Add_Opening({ Build-Menu })

# ---- refresh ----
function Update-UI {
    $s = Load-Status
    $name = Get-StateName $s
    $st = $States[$name]
    $tray.Icon = $Icons[$name]
    $tip = "LeakWatch: $($st.title)"
    $tray.Text = $tip.Substring(0, [Math]::Min(63, $tip.Length))

    $pic.Image = $WidgetImg[$name]
    $headline.Text = $st.title
    $btn.Text = $(if ($script:testing) { 'Testing...' } else { 'Test now' })
    $btn.Enabled = -not $script:testing
    $sub.Text = $(if ($s) { 'Last test: ' + (Format-Ago ([long]$s.epoch)) } else { '' })
    $details.Text = (Get-Details $s) -join "`n"
    $form.Height = $details.Bottom + 16
    Set-Rounded

    if ($script:widget.show) {
        if (-not $form.Visible) { $form.Show() }
        Send-ToBottom
    } elseif ($form.Visible) { $form.Hide() }
}

# Hourly scheduler + refresh every 20 s
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 20000
$timer.Add_Tick({
    $s = Load-Status
    $age = if ($s) { (Now) - [long]$s.epoch } else { [long]::MaxValue }
    if (-not $script:testing -and $age -ge $TestEvery -and ((Now) - $script:lastAttempt) -ge $RetryAfter) { Start-Test }
    Update-UI
})

# Watches the running test process
$procTimer = New-Object Windows.Forms.Timer
$procTimer.Interval = 1000
$procTimer.Add_Tick({
    if ($script:proc -and $script:proc.HasExited) {
        $procTimer.Stop()
        $script:testing = $false
        $script:proc = $null
        Update-UI
    }
})

# First test shortly after start (login), unless a recent result exists
$startTimer = New-Object Windows.Forms.Timer
$startTimer.Interval = 5000
$startTimer.Add_Tick({
    $startTimer.Stop()
    $s = Load-Status
    if (-not $s -or ((Now) - [long]$s.epoch) -ge $TestEvery) { Start-Test }
})

Update-UI
$timer.Start()
$startTimer.Start()
[Windows.Forms.Application]::Run()
$tray.Dispose()

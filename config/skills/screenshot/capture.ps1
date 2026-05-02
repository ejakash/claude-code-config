param(
    [Parameter(Position=0)]
    [ValidateSet("overview", "crop", "list", "list-windows", "window", "window-crop")]
    [string]$Mode = "overview",

    # For crop mode: which capture to zoom into
    [string]$CaptureId,

    # Crop region as percentages (0-100) of the full image
    [float]$Left = 0,
    [float]$Top = 0,
    [float]$Right = 100,
    [float]$Bottom = 100,

    # For list-windows: optional regex filter on window title
    [string]$Filter,

    # For window mode
    # NOTE: $Pid is a PowerShell automatic variable (current process ID).
    # Expose -Pid as the flag name but bind it internally to $TargetPid.
    [Parameter()][Alias('Pid')][int]$TargetPid,
    [IntPtr]$WindowHwnd = [IntPtr]::Zero,
    [string]$WindowTitle,
    # Optional process-name filter to disambiguate title collisions
    # (e.g. -WindowTitle 'WezTerm' -Proc 'wezterm-gui' excludes Firefox tabs)
    [string]$Proc,
    [ValidateSet('full','content','titlebar','left-half','right-half','top-half','bottom-half','center','top-strip')]
    [string]$Region = 'full',
    [ValidateSet('auto','printwindow','restore')]
    [string]$Strategy = 'auto',
    [switch]$Best,
    [switch]$First,

    [ValidateSet("pipe","json")]
    [string]$Format = "pipe",

    [switch]$DotSourceOnly
)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public class Win32
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool GetClientRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool ClientToScreen(IntPtr hWnd, ref POINT point);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetDpiForWindow(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);

    [DllImport("dwmapi.dll")]
    public static extern int DwmGetWindowAttribute(IntPtr hWnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);
}
'@
[Win32]::SetProcessDPIAware() | Out-Null
Add-Type -AssemblyName System.Windows.Forms,System.Drawing

# IMPORTANT: entries must be lowercase without .exe — Get-ProcessName normalizes before lookup
$PROBLEMATIC_PROCS = @('chrome','msedge','brave','opera','steam','vlc','mpv','obs64','wezterm-gui')
$SCREENSHOT_DIR = "$env:USERPROFILE\Pictures\Screenshots"
$TEMP_DIR = "$env:TEMP\claude-screenshots"
if (-not (Test-Path $TEMP_DIR)) { New-Item -ItemType Directory -Path $TEMP_DIR | Out-Null }

function Write-Result {
    param(
        [string]$Kind,
        # MUST be [ordered]@{} / OrderedDictionary — regular @{} has non-deterministic
        # ordering and will produce intermittent pipe-format breakage.
        [System.Collections.IDictionary]$Payload,
        [string]$Format = 'pipe'
    )
    if ($Format -eq 'json') {
        $obj = [ordered]@{ kind = $Kind }
        foreach ($k in $Payload.Keys) { $obj[$k] = $Payload[$k] }
        $obj | ConvertTo-Json -Compress -Depth 5 | Write-Host
        return
    }
    $parts = @($Kind)
    foreach ($key in $Payload.Keys) {
        $val = $Payload[$key]
        if ($key -in @('path','dims','captures','count')) { $parts += $val }
        else { $parts += "$key=$val" }
    }
    Write-Host ($parts -join '|')
}

function ConvertTo-SafeTitle {
    param([string]$Title)
    if ([string]::IsNullOrEmpty($Title)) { return '' }
    $sb = [System.Text.StringBuilder]::new()
    foreach ($c in $Title.ToCharArray()) {
        if ($c -eq '|' -or $c -eq "`n" -or $c -eq "`r" -or $c -eq '%') {
            [void]$sb.AppendFormat('%{0:X2}', [int]$c)
        } else {
            [void]$sb.Append($c)
        }
    }
    $sb.ToString()
}

function Get-ProcessName {
    param([string]$Name)
    ($Name -replace '\.exe$','').ToLowerInvariant()
}

function Apply-Region {
    param(
        [Parameter(Mandatory=$true)][hashtable]$Bounds,
        [Parameter(Mandatory=$true)][string]$Region
    )
    $EF = $Bounds.ExtendedFrame
    $CR = $Bounds.ClientRect
    switch ($Region) {
        'full' {
            return @{ Left = $EF.Left; Top = $EF.Top; Right = $EF.Right; Bottom = $EF.Bottom }
        }
        'content' {
            return @{ Left = $CR.Left; Top = $CR.Top; Right = $CR.Right; Bottom = $CR.Bottom }
        }
        'titlebar' {
            return @{ Left = $EF.Left; Top = $EF.Top; Right = $EF.Right; Bottom = $CR.Top }
        }
        'left-half' {
            $mid = [int](($EF.Left + $EF.Right) / 2)
            return @{ Left = $EF.Left; Top = $EF.Top; Right = $mid; Bottom = $EF.Bottom }
        }
        'right-half' {
            $mid = [int](($EF.Left + $EF.Right) / 2)
            return @{ Left = $mid; Top = $EF.Top; Right = $EF.Right; Bottom = $EF.Bottom }
        }
        'top-half' {
            $mid = [int](($EF.Top + $EF.Bottom) / 2)
            return @{ Left = $EF.Left; Top = $EF.Top; Right = $EF.Right; Bottom = $mid }
        }
        'bottom-half' {
            $mid = [int](($EF.Top + $EF.Bottom) / 2)
            return @{ Left = $EF.Left; Top = $mid; Right = $EF.Right; Bottom = $EF.Bottom }
        }
        'center' {
            $w = $EF.Right - $EF.Left
            $h = $EF.Bottom - $EF.Top
            return @{
                Left   = $EF.Left + [int]($w * 0.25)
                Right  = $EF.Left + [int]($w * 0.75)
                Top    = $EF.Top  + [int]($h * 0.25)
                Bottom = $EF.Top  + [int]($h * 0.75)
            }
        }
        'top-strip' {
            $h = $EF.Bottom - $EF.Top
            return @{
                Left   = $EF.Left
                Right  = $EF.Right
                Top    = $EF.Top
                Bottom = $EF.Top + [int]($h * 0.05)
            }
        }
        default {
            throw "Unknown region: $Region"
        }
    }
}

function Test-CaptureBlank {
    param([System.Drawing.Bitmap]$Bitmap)

    $W = $Bitmap.Width
    $H = $Bitmap.Height

    # 25 grid samples (5x5) — keep R/G/B components separately plus brightness sum
    $gridR = New-Object 'int[]' 25
    $gridG = New-Object 'int[]' 25
    $gridB = New-Object 'int[]' 25
    $gridSum = New-Object 'int[]' 25
    for ($j = 0; $j -lt 5; $j++) {
        for ($i = 0; $i -lt 5; $i++) {
            $x = [Math]::Min([int]($W * $i / 5 + $W / 10), $W - 1)
            $y = [Math]::Min([int]($H * $j / 5 + $H / 10), $H - 1)
            if ($x -lt 0) { $x = 0 }
            if ($y -lt 0) { $y = 0 }
            $p = $Bitmap.GetPixel($x, $y)
            $idx = $j * 5 + $i
            $gridR[$idx] = [int]$p.R
            $gridG[$idx] = [int]$p.G
            $gridB[$idx] = [int]$p.B
            $gridSum[$idx] = [int]$p.R + [int]$p.G + [int]$p.B
        }
    }

    # 9 center cluster samples (3x3 in middle 30%)
    $centerSum = New-Object 'int[]' 9
    for ($j = 0; $j -lt 3; $j++) {
        for ($i = 0; $i -lt 3; $i++) {
            $x = [Math]::Min([int]($W * 0.35 + $W * 0.15 * $i), $W - 1)
            $y = [Math]::Min([int]($H * 0.35 + $H * 0.15 * $j), $H - 1)
            if ($x -lt 0) { $x = 0 }
            if ($y -lt 0) { $y = 0 }
            $p = $Bitmap.GetPixel($x, $y)
            $centerSum[$j * 3 + $i] = [int]$p.R + [int]$p.G + [int]$p.B
        }
    }

    # Count near-black
    $centerBlack = 0
    foreach ($v in $centerSum) { if ($v -lt 30) { $centerBlack++ } }
    $overallBlack = 0
    foreach ($v in $gridSum) { if ($v -lt 30) { $overallBlack++ } }

    # Std dev across all 34 brightness sums (reported)
    $all = @($gridSum) + @($centerSum)
    $sum = 0.0
    foreach ($v in $all) { $sum += $v }
    $mean = $sum / $all.Count
    $sqAcc = 0.0
    foreach ($v in $all) { $d = $v - $mean; $sqAcc += $d * $d }
    $variance = $sqAcc / $all.Count
    $stddev = [Math]::Sqrt($variance)

    # Per-channel std dev across 25 grid samples (for low-variance rule — a
    # gradient like red→blue keeps R+G+B constant but varies per-channel,
    # so discriminating on the sum alone incorrectly flags gradients as blank).
    function _stddev {
        param([int[]]$arr)
        $s = 0.0
        foreach ($v in $arr) { $s += $v }
        $m = $s / $arr.Count
        $sq = 0.0
        foreach ($v in $arr) { $d = $v - $m; $sq += $d * $d }
        [Math]::Sqrt($sq / $arr.Count)
    }
    $stddevR = _stddev $gridR
    $stddevG = _stddev $gridG
    $stddevB = _stddev $gridB

    $isBlank = $false
    if ($centerBlack -ge 7) { $isBlank = $true }
    elseif ($overallBlack -ge 20) { $isBlank = $true }
    elseif ($W -ge 200 -and $H -ge 200) {
        # Uniform color check via median RGB
        $sortedR = @($gridR) | Sort-Object
        $sortedG = @($gridG) | Sort-Object
        $sortedB = @($gridB) | Sort-Object
        $medR = $sortedR[12]; $medG = $sortedG[12]; $medB = $sortedB[12]
        $matchCount = 0
        for ($k = 0; $k -lt 25; $k++) {
            if ([Math]::Abs($gridR[$k] - $medR) -le 5 -and
                [Math]::Abs($gridG[$k] - $medG) -le 5 -and
                [Math]::Abs($gridB[$k] - $medB) -le 5) {
                $matchCount++
            }
        }
        if ($matchCount -ge 23) { $isBlank = $true }
        elseif ($stddevR -lt 3 -and $stddevG -lt 3 -and $stddevB -lt 3) { $isBlank = $true }
    }

    @{
        IsBlank = $isBlank
        CenterBlack = $centerBlack
        OverallBlack = $overallBlack
        StdDev = $stddev
    }
}

function Get-WindowBounds {
    param([IntPtr]$Hwnd)

    # IsMinimized
    $isMin = [Win32]::IsIconic($Hwnd)
    # IsForeground
    $isFg = ([Win32]::GetForegroundWindow() -eq $Hwnd)

    # WindowRect via GetWindowRect
    $wr = New-Object Win32+RECT
    [void][Win32]::GetWindowRect($Hwnd, [ref]$wr)
    $windowRect = @{ Left = $wr.Left; Top = $wr.Top; Right = $wr.Right; Bottom = $wr.Bottom }

    # ExtendedFrame via DwmGetWindowAttribute (DWMWA_EXTENDED_FRAME_BOUNDS = 9)
    $ef = New-Object Win32+RECT
    $size = [System.Runtime.InteropServices.Marshal]::SizeOf([type]([Win32+RECT]))
    $hr = [Win32]::DwmGetWindowAttribute($Hwnd, 9, [ref]$ef, $size)
    if ($hr -eq 0) {
        $extendedFrame = @{ Left = $ef.Left; Top = $ef.Top; Right = $ef.Right; Bottom = $ef.Bottom }
    } else {
        $extendedFrame = $windowRect.Clone()  # fallback
    }

    # ClientRect (window-local) via GetClientRect, then convert top-left to screen via ClientToScreen
    $cr = New-Object Win32+RECT
    [void][Win32]::GetClientRect($Hwnd, [ref]$cr)
    $clientW = $cr.Right - $cr.Left
    $clientH = $cr.Bottom - $cr.Top
    $tl = New-Object Win32+POINT
    $tl.X = $cr.Left; $tl.Y = $cr.Top
    [void][Win32]::ClientToScreen($Hwnd, [ref]$tl)
    $clientRect = @{ Left = $tl.X; Top = $tl.Y; Right = $tl.X + $clientW; Bottom = $tl.Y + $clientH }

    # DPI
    $dpi = 96
    try { $dpi = [int][Win32]::GetDpiForWindow($Hwnd) } catch { }
    if ($dpi -le 0) { $dpi = 96 }

    # Monitor index — find which AllScreens entry contains the window center
    $monitor = 0
    try {
        $cx = [int](($extendedFrame.Left + $extendedFrame.Right) / 2)
        $cy = [int](($extendedFrame.Top + $extendedFrame.Bottom) / 2)
        $screens = [System.Windows.Forms.Screen]::AllScreens
        for ($k = 0; $k -lt $screens.Count; $k++) {
            $sb = $screens[$k].Bounds
            if ($cx -ge $sb.Left -and $cx -lt $sb.Right -and $cy -ge $sb.Top -and $cy -lt $sb.Bottom) {
                $monitor = $k
                break
            }
        }
    } catch { $monitor = 0 }

    # Z-order: walk GetWindow(hwnd, GW_HWNDPREV=3) upward; count steps to reach top.
    $zorder = 0
    $prev = $Hwnd
    while ($true) {
        $p = [Win32]::GetWindow($prev, 3)
        if ($p -eq [IntPtr]::Zero) { break }
        $zorder++
        $prev = $p
        if ($zorder -gt 1000) { break }  # safety cap
    }

    @{
        WindowRect    = $windowRect
        ExtendedFrame = $extendedFrame
        ClientRect    = $clientRect
        Monitor       = $monitor
        Dpi           = $dpi
        IsMinimized   = [bool]$isMin
        IsForeground  = [bool]$isFg
        ZOrder        = $zorder
    }
}

function Get-PidForHwnd {
    param([IntPtr]$Hwnd)
    $pid_ = [uint32]0
    [void][Win32]::GetWindowThreadProcessId($Hwnd, [ref]$pid_)
    $pid_
}

function Invoke-PrintWindow {
    param([IntPtr]$Hwnd, [hashtable]$Bounds)
    $EF = $Bounds.ExtendedFrame
    $w = $EF.Right - $EF.Left
    $h = $EF.Bottom - $EF.Top
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $hdc = $g.GetHdc()
        try {
            # PW_RENDERFULLCONTENT = 0x2 — captures DWM-rendered content, essential for modern windowed apps
            [void][Win32]::PrintWindow($Hwnd, $hdc, [uint32]2)
        } finally {
            $g.ReleaseHdc($hdc)
            $g.Dispose()
        }
    } catch {
        $bmp.Dispose()
        throw
    }
    $bmp
}

function Invoke-ScreenCopy {
    param([hashtable]$Bounds)
    $EF = $Bounds.ExtendedFrame
    $w = $EF.Right - $EF.Left
    $h = $EF.Bottom - $EF.Top
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $srcPoint = New-Object System.Drawing.Point($EF.Left, $EF.Top)
            $destPoint = [System.Drawing.Point]::Empty
            $size = New-Object System.Drawing.Size($w, $h)
            $g.CopyFromScreen($srcPoint, $destPoint, $size)
        } finally {
            $g.Dispose()
        }
    } catch {
        $bmp.Dispose()
        throw
    }
    $bmp
}

function Capture-Window {
    param([IntPtr]$Hwnd, [string]$Strategy = 'auto')

    $bounds = Get-WindowBounds -Hwnd $Hwnd
    $procName = 'unknown'
    try {
        $procId = Get-PidForHwnd -Hwnd $Hwnd
        $procName = Get-ProcessName (Get-Process -Id $procId -ErrorAction Stop).ProcessName
    } catch { }

    $useStrategy = $Strategy
    if ($useStrategy -eq 'auto') {
        if ($PROBLEMATIC_PROCS -contains $procName) { $useStrategy = 'restore' }
    }

    if ($useStrategy -in @('auto','printwindow')) {
        $bmp = Invoke-PrintWindow -Hwnd $Hwnd -Bounds $bounds
        try {
            $blank = Test-CaptureBlank -Bitmap $bmp
        } catch {
            $bmp.Dispose()
            throw
        }
        if (-not $blank.IsBlank) {
            return @{ Bitmap=$bmp; Strategy='printwindow'; Bounds=$bounds; BlankInfo=$blank }
        }
        if ($Strategy -eq 'printwindow') {
            $bmp.Dispose()
            throw "capture_failed|pw_blank=yes|center_black=$($blank.CenterBlack)/9|overall_black=$($blank.OverallBlack)/25"
        }
        $bmp.Dispose()
    }

    # restore strategy
    $wasMinimized = $bounds.IsMinimized
    if ($wasMinimized) {
        [void][Win32]::ShowWindow($Hwnd, 4)  # SW_SHOWNOACTIVATE — show without stealing keyboard focus
        # 150ms lets DWM finish the un-minimize animation on Win10/11 before we capture.
        # Could poll IsIconic or call DwmFlush instead, but this is simpler and sufficient in practice.
        Start-Sleep -Milliseconds 150
    }
    $fresh = Get-WindowBounds -Hwnd $Hwnd
    $bmp = Invoke-ScreenCopy -Bounds $fresh
    if ($wasMinimized) {
        [void][Win32]::ShowWindow($Hwnd, 6)  # SW_MINIMIZE
    }
    @{ Bitmap=$bmp; Strategy='restore'; Bounds=$fresh; BlankInfo=$null }
}

function Get-CandidateRanking {
    param([array]$Candidates)
    # Use all-Ascending via expression inversion so per-key direction is respected across
    # both Windows PowerShell 5.1 and pwsh 7. Mixing Ascending/Descending in Sort-Object
    # hashtables is buggy on some runtimes; this form is portable.
    #   - foreground: invert bool so true→false sorts before false→true (foreground wins)
    #   - minimized: bool directly; false→false sorts before true→true (visible wins)
    #   - ZOrder: lower wins (topmost)
    #   - Area: negate so larger wins ascending
    $Candidates | Sort-Object `
        @{ Expression = { -not [bool]$_.IsForeground }; Ascending = $true }, `
        @{ Expression = {      [bool]$_.IsMinimized    }; Ascending = $true }, `
        @{ Expression = {      [int]$_.ZOrder          }; Ascending = $true }, `
        @{ Expression = {    -([int]$_.Area)           }; Ascending = $true }
}

function Resolve-Ambiguity {
    param([array]$Matches, [switch]$Best, [switch]$First)
    $sorted = Get-CandidateRanking -Candidates $Matches
    if ($Best) {
        $m = @($sorted)[0]
        return @{ Hwnd = $m.Hwnd; Proc = $m.Proc; AutoResolved = 'best' }
    }
    if ($First) {
        $m = @($Matches)[0]
        return @{ Hwnd = $m.Hwnd; Proc = $m.Proc; AutoResolved = 'first' }
    }
    return @{ Ambiguous = $true; Candidates = @($sorted) }
}

function Resolve-Window {
    param(
        [string]$WindowTitle,
        [int]$TargetPid = 0,
        [IntPtr]$Hwnd = [IntPtr]::Zero,
        # Optional process-name filter. Disambiguates title collisions — e.g., searching
        # "WezTerm" with -Proc 'wezterm-gui' skips Firefox tabs whose title contains that
        # substring. Applied as an AND filter on top of -WindowTitle / -TargetPid results.
        [string]$Proc,
        [switch]$Best,
        [switch]$First
    )

    # 1. Direct HWND
    if ($Hwnd -ne [IntPtr]::Zero) {
        if ([Win32]::IsWindowVisible($Hwnd) -or [Win32]::IsIconic($Hwnd)) {
            $procId = Get-PidForHwnd -Hwnd $Hwnd
            $proc = try { Get-ProcessName (Get-Process -Id $procId -ErrorAction Stop).ProcessName } catch { 'unknown' }
            return @{ Hwnd = $Hwnd; Proc = $proc; AutoResolved = $null }
        }
        return @{ NoMatch = $true; Detail = 'invalid_hwnd' }
    }

    # Enumerate all candidates — use $script:all for closure semantics
    $script:all = @()
    $script:_targetPid = $TargetPid
    [Win32+EnumWindowsProc]$cb = {
        param($h, $lp)
        if (-not ([Win32]::IsWindowVisible($h) -or [Win32]::IsIconic($h))) { return $true }
        $len = [Win32]::GetWindowTextLength($h)
        if ($len -eq 0 -and $script:_targetPid -eq 0) { return $true }  # skip titleless unless filtering by pid
        $sb = New-Object System.Text.StringBuilder($len + 1)
        [void][Win32]::GetWindowText($h, $sb, $sb.Capacity)
        $title = $sb.ToString()
        $pid_ = Get-PidForHwnd -Hwnd $h
        $procName = try { Get-ProcessName (Get-Process -Id $pid_ -ErrorAction Stop).ProcessName } catch { 'unknown' }
        $b = Get-WindowBounds -Hwnd $h
        $area = ($b.ExtendedFrame.Right - $b.ExtendedFrame.Left) * ($b.ExtendedFrame.Bottom - $b.ExtendedFrame.Top)
        $script:all += @{
            Hwnd = $h; Pid = $pid_; Proc = $procName; Title = $title
            Bounds = $b; Area = $area
            IsForeground = $b.IsForeground; IsMinimized = $b.IsMinimized; ZOrder = $b.ZOrder
            LastActive = 0
        }
        return $true
    }
    [void][Win32]::EnumWindows($cb, [IntPtr]::Zero)
    $all = $script:all
    # Clear script-scope leak so stale data doesn't linger between calls
    $script:all = $null
    $script:_targetPid = $null

    # Apply optional -Proc filter across all candidates up front
    $procFilter = if ($Proc) { (Get-ProcessName $Proc) } else { $null }
    if ($procFilter) {
        $all = @($all | Where-Object { $_.Proc -eq $procFilter })
    }

    # 2. Target PID
    if ($TargetPid -ne 0) {
        $cands = @($all | Where-Object { $_.Pid -eq $TargetPid })
        $matchCount = $cands.Count
        if ($matchCount -eq 0) { return @{ NoMatch = $true; Detail = "no_match|pid=$TargetPid" } }
        if ($matchCount -eq 1) {
            $m = $cands[0]
            return @{ Hwnd = $m.Hwnd; Proc = $m.Proc; AutoResolved = $null }
        }
        return Resolve-Ambiguity -Matches $cands -Best:$Best -First:$First
    }

    # 3. Proc-only (no title/pid) — pick from candidates filtered by -Proc
    if ([string]::IsNullOrEmpty($WindowTitle) -and $procFilter) {
        $cands = $all
        $matchCount = $cands.Count
        if ($matchCount -eq 0) { return @{ NoMatch = $true; Detail = "no_match|proc=$procFilter" } }
        if ($matchCount -eq 1) {
            $m = $cands[0]
            return @{ Hwnd = $m.Hwnd; Proc = $m.Proc; AutoResolved = 'proc' }
        }
        # Tier: single foreground / single visible before ambiguous
        $fg = @($cands | Where-Object { $_.IsForeground })
        if ($fg.Count -eq 1) { return @{ Hwnd = $fg[0].Hwnd; Proc = $fg[0].Proc; AutoResolved = 'foreground' } }
        $vis = @($cands | Where-Object { -not $_.IsMinimized })
        if ($vis.Count -eq 1) { return @{ Hwnd = $vis[0].Hwnd; Proc = $vis[0].Proc; AutoResolved = 'visible' } }
        return Resolve-Ambiguity -Matches $cands -Best:$Best -First:$First
    }

    # 4. Window title substring match
    if (-not [string]::IsNullOrEmpty($WindowTitle)) {
        $lc = $WindowTitle.ToLowerInvariant()
        $cands = @($all | Where-Object { $_.Title.ToLowerInvariant().Contains($lc) })
        $matchCount = $cands.Count
        if ($matchCount -eq 0) {
            $detail = "no_match|title=$(ConvertTo-SafeTitle $WindowTitle)"
            if ($procFilter) { $detail += "|proc=$procFilter" }
            return @{ NoMatch = $true; Detail = $detail }
        }

        # Tier 1: exactly one exact-title match
        $exact = @($cands | Where-Object { $_.Title -eq $WindowTitle })
        if ($exact.Count -eq 1) {
            $m = $exact[0]
            return @{ Hwnd = $m.Hwnd; Proc = $m.Proc; AutoResolved = 'exact_title' }
        }
        # Tier 2: exactly one foreground
        $fg = @($cands | Where-Object { $_.IsForeground })
        if ($fg.Count -eq 1) {
            $m = $fg[0]
            return @{ Hwnd = $m.Hwnd; Proc = $m.Proc; AutoResolved = 'foreground' }
        }
        # Tier 3: exactly one visible
        $vis = @($cands | Where-Object { -not $_.IsMinimized })
        if ($vis.Count -eq 1) {
            $m = $vis[0]
            return @{ Hwnd = $m.Hwnd; Proc = $m.Proc; AutoResolved = 'visible' }
        }
        if ($matchCount -eq 1) {
            $m = $cands[0]
            return @{ Hwnd = $m.Hwnd; Proc = $m.Proc; AutoResolved = $null }
        }
        return Resolve-Ambiguity -Matches $cands -Best:$Best -First:$First
    }

    return @{ NoMatch = $true; Detail = 'no_target_specified' }
}

if ($DotSourceOnly) { return }

# Cleanup: remove temp captures older than 1 hour
Get-ChildItem $TEMP_DIR -Filter "capture_*.png" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-1) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

if ($Mode -eq "list") {
    # List available captures for reference
    $captures = Get-ChildItem $TEMP_DIR -Filter "capture_*.png" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object { $_.BaseName -replace '^capture_', '' }
    $value = if ($captures) { $captures -join ',' } else { 'none' }
    Write-Result -Kind 'available_captures' -Payload ([ordered]@{ captures = $value }) -Format $Format
    exit 0
}

if ($Mode -eq "overview") {
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds

    # Generate unique capture ID
    $captureId = Get-Date -Format 'yyyyMMdd_HHmmss_fff'

    # Capture full screen at native resolution
    $full = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $g = [System.Drawing.Graphics]::FromImage($full)
    $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $g.Dispose()

    # Save full-res with unique ID for later cropping
    $tempPath = Join-Path $TEMP_DIR "capture_${captureId}.png"
    $full.Save($tempPath)

    # Create overview (1200px long edge, ~1080 tokens)
    $ratio = [Math]::Min(1200.0 / $bounds.Width, 1200.0 / $bounds.Height)
    $ow = [int]($bounds.Width * $ratio)
    $oh = [int]($bounds.Height * $ratio)
    $overview = New-Object System.Drawing.Bitmap($ow, $oh)
    $g2 = [System.Drawing.Graphics]::FromImage($overview)
    $g2.InterpolationMode = 'HighQualityBicubic'
    $g2.DrawImage($full, 0, 0, $ow, $oh)
    $g2.Dispose()
    $full.Dispose()

    $outPath = Join-Path $SCREENSHOT_DIR "Screenshot ${captureId}.png"
    $overview.Save($outPath)
    $overview.Dispose()

    Write-Result -Kind 'overview' -Payload ([ordered]@{
        path = $outPath
        dims = "${ow}x${oh}"
        capture_id = $captureId
    }) -Format $Format
}
elseif ($Mode -eq "crop") {
    if (-not $CaptureId) {
        # Default to most recent capture
        $latest = Get-ChildItem $TEMP_DIR -Filter "capture_*.png" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $latest) {
            Write-Error "No captures available. Run 'overview' first."
            exit 1
        }
        $CaptureId = $latest.BaseName -replace '^capture_', ''
    }

    $tempPath = Join-Path $TEMP_DIR "capture_${CaptureId}.png"
    if (-not (Test-Path $tempPath)) {
        Write-Error "Capture '$CaptureId' not found. Run 'list' to see available captures."
        exit 1
    }

    $full = [System.Drawing.Image]::FromFile($tempPath)

    # Convert percentage coordinates to pixels
    $px_left   = [int]($Left   / 100.0 * $full.Width)
    $px_top    = [int]($Top    / 100.0 * $full.Height)
    $px_right  = [int]($Right  / 100.0 * $full.Width)
    $px_bottom = [int]($Bottom / 100.0 * $full.Height)
    $px_w = $px_right - $px_left
    $px_h = $px_bottom - $px_top

    # Crop from full-res
    $cropRect = New-Object System.Drawing.Rectangle($px_left, $px_top, $px_w, $px_h)
    $cropped = ([System.Drawing.Bitmap]$full).Clone($cropRect, $full.PixelFormat)
    $full.Dispose()

    # Scale crop to 1568px long edge for optimal Claude processing
    $maxDim = 1568.0
    $ratio = [Math]::Min($maxDim / $cropped.Width, $maxDim / $cropped.Height)
    if ($ratio -lt 1.0) {
        $nw = [int]($cropped.Width * $ratio)
        $nh = [int]($cropped.Height * $ratio)
    } else {
        $nw = $cropped.Width
        $nh = $cropped.Height
    }
    $final = New-Object System.Drawing.Bitmap($nw, $nh)
    $g = [System.Drawing.Graphics]::FromImage($final)
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.DrawImage($cropped, 0, 0, $nw, $nh)
    $g.Dispose()
    $cropped.Dispose()

    $outPath = Join-Path $SCREENSHOT_DIR "Screenshot ${CaptureId}_crop.png"
    $final.Save($outPath)
    $final.Dispose()

    Write-Result -Kind 'crop' -Payload ([ordered]@{
        path = $outPath
        dims = "${nw}x${nh}"
        capture_id = $CaptureId
        region = "${Left},${Top},${Right},${Bottom}"
    }) -Format $Format
}
elseif ($Mode -eq "list-windows") {
    $script:windows = @()
    [Win32+EnumWindowsProc]$callback = {
        param($h, $lp)
        if (-not ([Win32]::IsWindowVisible($h) -or [Win32]::IsIconic($h))) { return $true }
        $len = [Win32]::GetWindowTextLength($h)
        if ($len -eq 0) { return $true }  # skip title-less windows
        $sb = New-Object System.Text.StringBuilder($len + 1)
        [void][Win32]::GetWindowText($h, $sb, $sb.Capacity)
        $title = $sb.ToString()
        # Optional filter
        if ($script:_filter -and ($title -notmatch $script:_filter)) { return $true }
        $pid_ = Get-PidForHwnd -Hwnd $h
        $procName = try { Get-ProcessName (Get-Process -Id $pid_ -ErrorAction Stop).ProcessName } catch { 'unknown' }
        $b = Get-WindowBounds -Hwnd $h
        $script:windows += [pscustomobject]@{ Hwnd = $h; Pid = $pid_; Proc = $procName; Title = $title; Bounds = $b }
        return $true
    }
    $script:_filter = $Filter
    [void][Win32]::EnumWindows($callback, [IntPtr]::Zero)
    # Copy to a differently-named local: at script scope `$windows` aliases
    # `$script:windows`, so nulling the latter would also clear the former.
    $winList = @($script:windows)
    # Clear script-scope leak
    $script:windows = $null
    $script:_filter = $null

    # Emit count header
    Write-Result -Kind 'windows' -Payload ([ordered]@{ count = $winList.Count }) -Format $Format

    # Sort: foreground first, then visible, then by title (all-Ascending for portability)
    $sorted = $winList | Sort-Object `
        @{ Expression = { -not [bool]$_.Bounds.IsForeground }; Ascending = $true }, `
        @{ Expression = {      [bool]$_.Bounds.IsMinimized    }; Ascending = $true }, `
        @{ Expression = {      $_.Title                        }; Ascending = $true }

    foreach ($w in $sorted) {
        $payload = [ordered]@{
            hwnd = $w.Hwnd
            pid  = $w.Pid
            proc = $w.Proc
            title = (ConvertTo-SafeTitle $w.Title)
            rect = "$($w.Bounds.ExtendedFrame.Left),$($w.Bounds.ExtendedFrame.Top),$($w.Bounds.ExtendedFrame.Right),$($w.Bounds.ExtendedFrame.Bottom)"
            client = "$($w.Bounds.ClientRect.Left),$($w.Bounds.ClientRect.Top),$($w.Bounds.ClientRect.Right),$($w.Bounds.ClientRect.Bottom)"
            monitor = $w.Bounds.Monitor
            state = if ($w.Bounds.IsMinimized) { 'minimized' } else { 'visible' }
            dpi = $w.Bounds.Dpi
            focus = if ($w.Bounds.IsForeground) { 'yes' } else { 'no' }
            zorder = $w.Bounds.ZOrder
        }
        Write-Result -Kind 'window' -Payload $payload -Format $Format
    }
}
elseif ($Mode -eq "window") {
    $resolved = Resolve-Window -WindowTitle $WindowTitle -TargetPid $TargetPid -Hwnd $WindowHwnd -Proc $Proc -Best:$Best -First:$First

    if ($resolved.NoMatch) {
        Write-Result -Kind 'error' -Payload ([ordered]@{ reason = 'no_match'; detail = $resolved.Detail }) -Format $Format
        exit 1
    }
    if ($resolved.Ambiguous) {
        Write-Result -Kind 'error' -Payload ([ordered]@{ reason = 'ambiguous'; matches = $resolved.Candidates.Count }) -Format $Format
        foreach ($c in $resolved.Candidates) {
            $payload = [ordered]@{
                hwnd = $c.Hwnd
                pid  = $c.Pid
                proc = $c.Proc
                title = (ConvertTo-SafeTitle $c.Title)
                rect = "$($c.Bounds.ExtendedFrame.Left),$($c.Bounds.ExtendedFrame.Top),$($c.Bounds.ExtendedFrame.Right),$($c.Bounds.ExtendedFrame.Bottom)"
                focus = if ($c.Bounds.IsForeground) { 'yes' } else { 'no' }
                zorder = $c.Bounds.ZOrder
                state = if ($c.Bounds.IsMinimized) { 'minimized' } else { 'visible' }
                last_active = $c.LastActive
            }
            Write-Result -Kind 'window' -Payload $payload -Format $Format
        }
        exit 2
    }

    $captureId = Get-Date -Format 'yyyyMMdd_HHmmss_fff'

    try {
        $cap = Capture-Window -Hwnd $resolved.Hwnd -Strategy $Strategy
    } catch {
        Write-Result -Kind 'error' -Payload ([ordered]@{
            reason = 'capture_failed'
            hwnd = $resolved.Hwnd
            detail = "$_"
        }) -Format $Format
        exit 3
    }

    # Apply region — map screen-space rect to bitmap-local rect
    # NB: use a distinct variable name; PowerShell variables are case-insensitive,
    # so `$region = ...` would clobber the `$Region` param string.
    $regionRect = Apply-Region -Bounds $cap.Bounds -Region $Region
    $lx = $regionRect.Left - $cap.Bounds.ExtendedFrame.Left
    $ly = $regionRect.Top - $cap.Bounds.ExtendedFrame.Top
    $lw = $regionRect.Right - $regionRect.Left
    $lh = $regionRect.Bottom - $regionRect.Top

    # Guard against degenerate rectangles (borderless windows can produce 0-height titlebar, etc.)
    if ($lw -le 0 -or $lh -le 0) {
        $cap.Bitmap.Dispose()
        Write-Result -Kind 'error' -Payload ([ordered]@{
            reason = 'degenerate_region'
            hwnd = $resolved.Hwnd
            region = $Region
            detail = "region=${Region} produced ${lw}x${lh}"
        }) -Format $Format
        exit 4
    }

    # Clamp to bitmap bounds (defense against slight off-by-one)
    $lx = [Math]::Max(0, $lx); $ly = [Math]::Max(0, $ly)
    $lw = [Math]::Min($lw, $cap.Bitmap.Width - $lx)
    $lh = [Math]::Min($lh, $cap.Bitmap.Height - $ly)

    $cropRect = New-Object System.Drawing.Rectangle($lx, $ly, $lw, $lh)
    $cropped = ([System.Drawing.Bitmap]$cap.Bitmap).Clone($cropRect, $cap.Bitmap.PixelFormat)
    $cap.Bitmap.Dispose()

    # Save full-res temp for window-crop reuse
    $tempPath = Join-Path $TEMP_DIR "capture_${captureId}.png"
    $cropped.Save($tempPath)

    # Scale to 1568px long edge
    $maxDim = 1568.0
    $ratio = [Math]::Min($maxDim / $cropped.Width, $maxDim / $cropped.Height)
    if ($ratio -lt 1.0) {
        $nw = [int]($cropped.Width * $ratio)
        $nh = [int]($cropped.Height * $ratio)
    } else {
        $nw = $cropped.Width
        $nh = $cropped.Height
    }
    $scaled = New-Object System.Drawing.Bitmap($nw, $nh)
    $g = [System.Drawing.Graphics]::FromImage($scaled)
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.DrawImage($cropped, 0, 0, $nw, $nh)
    $g.Dispose()
    $cropped.Dispose()

    $outPath = Join-Path $SCREENSHOT_DIR "Screenshot ${captureId}_window.png"
    $scaled.Save($outPath)
    $scaled.Dispose()

    $payload = [ordered]@{
        path = $outPath
        dims = "${nw}x${nh}"
        capture_id = $captureId
        hwnd = $resolved.Hwnd
        proc = $resolved.Proc
        region = $Region
        strategy = $cap.Strategy
        window_rect = "$($cap.Bounds.ExtendedFrame.Left),$($cap.Bounds.ExtendedFrame.Top),$($cap.Bounds.ExtendedFrame.Right),$($cap.Bounds.ExtendedFrame.Bottom)"
        captured_rect = "$($regionRect.Left),$($regionRect.Top),$($regionRect.Right),$($regionRect.Bottom)"
    }
    if ($resolved.AutoResolved) {
        $payload['auto_resolved'] = "yes|$($resolved.AutoResolved)"
    }
    Write-Result -Kind 'window' -Payload $payload -Format $Format
}
elseif ($Mode -eq "window-crop") {
    if (-not $CaptureId) {
        Write-Result -Kind 'error' -Payload ([ordered]@{ reason = 'missing_capture_id' }) -Format $Format
        exit 1
    }
    $tempPath = Join-Path $TEMP_DIR "capture_${CaptureId}.png"
    if (-not (Test-Path $tempPath)) {
        Write-Result -Kind 'error' -Payload ([ordered]@{ reason = 'capture_not_found'; capture_id = $CaptureId }) -Format $Format
        exit 1
    }

    $full = [System.Drawing.Image]::FromFile($tempPath)

    # Convert percentages to pixels (window-relative)
    $px_left   = [int]($Left   / 100.0 * $full.Width)
    $px_top    = [int]($Top    / 100.0 * $full.Height)
    $px_right  = [int]($Right  / 100.0 * $full.Width)
    $px_bottom = [int]($Bottom / 100.0 * $full.Height)
    $px_w = $px_right - $px_left
    $px_h = $px_bottom - $px_top

    if ($px_w -le 0 -or $px_h -le 0) {
        $full.Dispose()
        Write-Result -Kind 'error' -Payload ([ordered]@{ reason = 'degenerate_crop'; region_pct = "$Left,$Top,$Right,$Bottom" }) -Format $Format
        exit 4
    }

    $cropRect = New-Object System.Drawing.Rectangle($px_left, $px_top, $px_w, $px_h)
    $cropped = ([System.Drawing.Bitmap]$full).Clone($cropRect, $full.PixelFormat)
    $full.Dispose()

    # Scale to 1568px long edge
    $maxDim = 1568.0
    $ratio = [Math]::Min($maxDim / $cropped.Width, $maxDim / $cropped.Height)
    if ($ratio -lt 1.0) {
        $nw = [int]($cropped.Width * $ratio)
        $nh = [int]($cropped.Height * $ratio)
    } else {
        $nw = $cropped.Width
        $nh = $cropped.Height
    }
    $scaled = New-Object System.Drawing.Bitmap($nw, $nh)
    $g = [System.Drawing.Graphics]::FromImage($scaled)
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.DrawImage($cropped, 0, 0, $nw, $nh)
    $g.Dispose()
    $cropped.Dispose()

    $outPath = Join-Path $SCREENSHOT_DIR "Screenshot ${CaptureId}_window_crop.png"
    $scaled.Save($outPath)
    $scaled.Dispose()

    Write-Result -Kind 'window-crop' -Payload ([ordered]@{
        path = $outPath
        dims = "${nw}x${nh}"
        capture_id = $CaptureId
        region_pct = "$Left,$Top,$Right,$Bottom"
    }) -Format $Format
}

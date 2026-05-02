# Smart Window-Targeted Screenshots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing screenshot skill to support window-aware capture (enumerate, target by title/PID/HWND, crop to content area) while preserving 100% backwards compatibility with existing `overview`/`crop`/`list` modes.

**Architecture:** Single PowerShell script (`capture.ps1`) gains a shared output emitter, expanded Win32 P/Invoke surface, five pure helpers, and three new modes. Pure helpers are unit-tested with Pester; Win32/GDI paths are smoke-tested via a fixed checklist on the live desktop. No new files added — the skill stays single-script by design.

**Tech Stack:** PowerShell 5.1+ (Windows PowerShell or PowerShell 7), Win32 P/Invoke (user32.dll, dwmapi.dll), System.Drawing, Pester v5+ (for pure-function tests).

---

## Context for the Engineer

**What exists today:** `~/.claude/skills/screenshot/capture.ps1` — a ~130-line script with three modes (`overview`, `crop`, `list`) that captures the primary screen at native resolution, crops by screen-relative percentage, emits pipe-delimited output. Already has `SetProcessDPIAware()` and a 1-hour temp-file cleanup.

**What you're building:** See `docs/superpowers/specs/2026-04-16-smart-screenshots-design.md` for the approved design. Read it before starting Task 1.

**Commit/deploy workflow:** Task 0 migrates the skill into this repo and replaces `~/.claude/skills/screenshot/` with a symlink. After that, the skill is version-controlled directly: implementation happens in `config/skills/screenshot/`, each task ends with a real `git commit`, and the final Task N writes a single changelog entry documenting the migration and feature so other machines can adopt it.

**Testing approach:**
- **Pester unit tests** for pure helpers (no Win32 side effects): `Apply-Region`, `Test-CaptureBlank`, title URL-encoding, process-name normalization, candidate ranking. Tests live at `config/skills/screenshot/tests/capture.Tests.ps1` in this repo.
- **Smoke tests** for Win32-dependent paths (modes that touch actual windows): a numbered checklist the engineer runs against their live desktop. The spec's Testing section has the canonical checklist; each task below references relevant items.

**Path shorthand:** throughout this plan, `$REPO` = `/mnt/d/labs/claude-code-optimizations`. All implementation paths use `$REPO/config/skills/screenshot/`. The live symlink at `~/.claude/skills/screenshot/` transparently resolves to the same files.

**File layout inside `capture.ps1`** (enforce this ordering with section banners):

```
1. param() block
2. [DPI]::SetProcessDPIAware() + Add-Type (P/Invoke)
3. Constants ($PROBLEMATIC_PROCS, $TEMP_DIR, $SCREENSHOT_DIR)
4. Helpers (in dependency order):
     Write-Result
     ConvertTo-SafeTitle
     Get-ProcessName
     Get-WindowBounds
     Apply-Region
     Test-CaptureBlank
     Capture-Window
     Resolve-Window
5. Mode dispatch (switch on $Mode)
```

---

## Task 0: Migrate skill into repo + symlink

**Goal:** Move `~/.claude/skills/screenshot/` into `$REPO/config/skills/screenshot/`, replace the original with a symlink, verify the skill still works from the symlinked path.

**Files:**
- Move: `~/.claude/skills/screenshot/{capture.ps1,SKILL.md}` → `$REPO/config/skills/screenshot/`
- Create: symlink `~/.claude/skills/screenshot` → `$REPO/config/skills/screenshot`

- [ ] **Step 1: Verify the destination doesn't already exist**

Run: `ls $REPO/config/skills/screenshot 2>/dev/null`
Expected: no output (doesn't exist) OR empty/only irrelevant files. If it has a `capture.ps1` already, STOP and ask the user — there's pre-existing state to reconcile.

- [ ] **Step 2: Copy the skill into the repo**

```bash
mkdir -p /mnt/d/labs/claude-code-optimizations/config/skills/screenshot
cp ~/.claude/skills/screenshot/capture.ps1 /mnt/d/labs/claude-code-optimizations/config/skills/screenshot/
cp ~/.claude/skills/screenshot/SKILL.md    /mnt/d/labs/claude-code-optimizations/config/skills/screenshot/
```

- [ ] **Step 3: Sanity-check the copy**

Run: `diff ~/.claude/skills/screenshot/capture.ps1 /mnt/d/labs/claude-code-optimizations/config/skills/screenshot/capture.ps1`
Expected: no output (files identical).

- [ ] **Step 4: Replace the live location with a symlink**

```bash
rm ~/.claude/skills/screenshot/capture.ps1 ~/.claude/skills/screenshot/SKILL.md
rmdir ~/.claude/skills/screenshot
ln -s /mnt/d/labs/claude-code-optimizations/config/skills/screenshot ~/.claude/skills/screenshot
```

- [ ] **Step 5: Smoke-test the skill from the symlinked path**

Run: `powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w ~/.claude/skills/screenshot/capture.ps1)" -Mode overview`
Expected: same output as before, no errors. PNG saved to `Pictures\Screenshots`. The resolved Windows path should now look like `D:\labs\claude-code-optimizations\config\skills\screenshot\capture.ps1` (faster — native Windows filesystem, not `\\wsl$\...`).

- [ ] **Step 6: Commit the migration**

```bash
git -C /mnt/d/labs/claude-code-optimizations add config/skills/screenshot/
git -C /mnt/d/labs/claude-code-optimizations commit -m "chore: migrate screenshot skill into repo for direct version control"
```

- [ ] **Step 7: Checkpoint.** Skill is now version-controlled. All subsequent tasks work in `$REPO/config/skills/screenshot/`.

---

## Task 1: Set up Pester test harness and shared output helper

**Files:**
- Create: `$REPO/config/skills/screenshot/tests/capture.Tests.ps1`
- Modify: `$REPO/config/skills/screenshot/capture.ps1` (add `-Format` param, insert `Write-Result` helper, route existing three modes through it)

- [ ] **Step 1: Verify Pester is available**

Run in PowerShell (from Windows, not WSL): `powershell.exe -Command "Get-Module -ListAvailable Pester | Select-Object Name, Version"`
Expected: Pester version 5.x or later. If missing, install: `Install-Module Pester -Force -SkipPublisherCheck`.

- [ ] **Step 2: Create test file skeleton**

```powershell
# capture.Tests.ps1
BeforeAll {
    $script:CapturePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'capture.ps1'
    . $script:CapturePath -DotSourceOnly  # New flag — exits after helpers defined
}

Describe 'Write-Result' {
    Context 'pipe format' {
        It 'emits existing overview format verbatim' {
            $out = Write-Result -Kind 'overview' -Payload ([ordered]@{
                path = 'C:\x.png'; dims = '1200x675'; capture_id = '20260416_120000_000'
            }) -Format 'pipe' 6>&1
            $out | Should -Be 'overview|C:\x.png|1200x675|capture_id=20260416_120000_000'
        }
    }
    Context 'json format' {
        It 'emits one-line compact JSON with same fields' {
            $out = Write-Result -Kind 'overview' -Payload ([ordered]@{ path = 'C:\x.png' }) -Format 'json' 6>&1
            $json = $out | ConvertFrom-Json
            $json.kind | Should -Be 'overview'
            $json.path | Should -Be 'C:\x.png'
        }
    }
}
```

- [ ] **Step 3: Run test — expect FAIL**

Run: `powershell.exe -Command "Invoke-Pester -Path $REPO/config/skills/screenshot/tests/capture.Tests.ps1"`
Expected: failures — helper doesn't exist yet, `-DotSourceOnly` flag doesn't exist.

- [ ] **Step 4: Add `-Format` and `-DotSourceOnly` params + Write-Result helper**

In `capture.ps1` `param()` block, add:
```powershell
    [ValidateSet("pipe","json")]
    [string]$Format = "pipe",

    [switch]$DotSourceOnly
```

After the DPI line and Add-Type, before existing mode logic, add:
```powershell
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
    # Pipe format: kind|value1|value2|... with key=value pairs per spec
    $parts = @($Kind)
    foreach ($key in $Payload.Keys) {
        $val = $Payload[$key]
        if ($key -in @('path','dims')) { $parts += $val }
        else { $parts += "$key=$val" }
    }
    Write-Host ($parts -join '|')
}

if ($DotSourceOnly) { return }
```

Refactor existing `overview`, `crop`, `list` emits to call `Write-Result` with ordered hashtables that reproduce byte-identical output.

- [ ] **Step 5: Run test — expect PASS**

Run: `powershell.exe -Command "Invoke-Pester -Path $REPO/config/skills/screenshot/tests/capture.Tests.ps1"`
Expected: both tests pass.

- [ ] **Step 6: Backwards-compat smoke test**

Run: `powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w ~/.claude/skills/screenshot/capture.ps1)" -Mode overview`
Expected: output line starts with `overview|` and ends with `capture_id=<timestamp>` — byte-identical to pre-change format. Visually confirm the saved PNG exists and looks correct.

- [ ] **Step 7: Commit**

```bash
git -C /mnt/d/labs/claude-code-optimizations add config/skills/screenshot/
git -C /mnt/d/labs/claude-code-optimizations commit -m "feat(screenshot): add -Format flag and Write-Result emitter"
```

---

## Task 2: Extend P/Invoke surface and add constants

**Files:**
- Modify: `$REPO/config/skills/screenshot/capture.ps1` (extend `Add-Type` block, add constants)

- [ ] **Step 1: Write a smoke-test script**

Create `$REPO/config/skills/screenshot/tests/pinvoke.smoke.ps1`:
```powershell
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'capture.ps1') -DotSourceOnly
$hwnd = [Win32]::GetForegroundWindow()
if ($hwnd -eq [IntPtr]::Zero) { throw 'GetForegroundWindow returned zero' }
$rect = New-Object Win32+RECT
$ok = [Win32]::GetWindowRect($hwnd, [ref]$rect)
if (-not $ok) { throw 'GetWindowRect failed' }
Write-Host "OK hwnd=$hwnd rect=$($rect.Left),$($rect.Top),$($rect.Right),$($rect.Bottom)"
```

- [ ] **Step 2: Run smoke — expect FAIL**

Run: `powershell.exe -File "$(wslpath -w $REPO/config/skills/screenshot/tests/pinvoke.smoke.ps1)"`
Expected: error, `Win32` type not defined.

- [ ] **Step 3: Replace the minimal `DPI` Add-Type with a full `Win32` class**

Replace the existing one-liner Add-Type with a block that defines class `Win32` exporting these static methods (all from `user32.dll` unless noted):

- `SetProcessDPIAware` (keep current behavior)
- `EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam)` with a matching delegate type
- `GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount)` returns int
- `GetWindowTextLength(IntPtr hWnd)` returns int
- `GetWindowRect(IntPtr hWnd, out RECT rect)` — RECT struct with `Left, Top, Right, Bottom`
- `GetClientRect(IntPtr hWnd, out RECT rect)`
- `ClientToScreen(IntPtr hWnd, ref POINT point)` — POINT struct with `X, Y`
- `IsIconic(IntPtr hWnd)` returns bool
- `IsWindowVisible(IntPtr hWnd)` returns bool
- `ShowWindow(IntPtr hWnd, int nCmdShow)` returns bool (SW_SHOWNOACTIVATE=4, SW_MINIMIZE=6, SW_RESTORE=9)
- `PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint flags)` returns bool (PW_RENDERFULLCONTENT=2)
- `GetWindowThreadProcessId(IntPtr hWnd, out uint processId)` returns uint
- `MonitorFromWindow(IntPtr hWnd, uint flags)` returns IntPtr (MONITOR_DEFAULTTONEAREST=2)
- `GetForegroundWindow()` returns IntPtr
- `GetDpiForWindow(IntPtr hWnd)` returns uint (Win10 1607+; fall back to 96 if the call fails)
- `GetWindow(IntPtr hWnd, uint uCmd)` returns IntPtr (GW_HWNDPREV=3, used for Z-order walk in Task 6)

From `dwmapi.dll`:
- `DwmGetWindowAttribute(IntPtr hWnd, int attr, out RECT rect, int sz)` returns int HRESULT (attr 9 = DWMWA_EXTENDED_FRAME_BOUNDS)

Call `[Win32]::SetProcessDPIAware()` right after Add-Type.

After the `Add-Type` block, add constants:
```powershell
$PROBLEMATIC_PROCS = @('chrome','msedge','brave','opera','steam','vlc','mpv','obs64')
$SCREENSHOT_DIR = "$env:USERPROFILE\Pictures\Screenshots"
$TEMP_DIR = "$env:TEMP\claude-screenshots"
if (-not (Test-Path $TEMP_DIR)) { New-Item -ItemType Directory -Path $TEMP_DIR | Out-Null }
```

Update existing overview/crop code to reference `$SCREENSHOT_DIR` / `$TEMP_DIR` (replacing the local `$screenshotDir`/`$tempDir` definitions — DRY).

- [ ] **Step 4: Run smoke — expect PASS**

Run: `powershell.exe -File "$(wslpath -w $REPO/config/skills/screenshot/tests/pinvoke.smoke.ps1)"`
Expected: `OK hwnd=<N> rect=<L>,<T>,<R>,<B>` with nonzero handle and sensible coordinates.

- [ ] **Step 5: Backwards-compat re-check**

Run: `powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w ~/.claude/skills/screenshot/capture.ps1)" -Mode overview`
Expected: still works, output unchanged from Task 1.

- [ ] **Step 6: Checkpoint** — Win32 P/Invoke surface is ready.

---

## Task 3: Helper — `ConvertTo-SafeTitle` and `Get-ProcessName` (pure, TDD)

**Files:**
- Modify: `$REPO/config/skills/screenshot/capture.ps1` (add two helpers)
- Modify: `$REPO/config/skills/screenshot/tests/capture.Tests.ps1` (add tests)

- [ ] **Step 1: Write failing tests**

Add to `capture.Tests.ps1`:
```powershell
Describe 'ConvertTo-SafeTitle' {
    It 'URL-encodes pipe, newline, and percent' {
        ConvertTo-SafeTitle "foo|bar`nbaz%qux" | Should -Be 'foo%7Cbar%0Abaz%25qux'
    }
    It 'passes through plain ASCII' {
        ConvertTo-SafeTitle 'Claude Code - WezTerm' | Should -Be 'Claude Code - WezTerm'
    }
    It 'handles empty string' {
        ConvertTo-SafeTitle '' | Should -Be ''
    }
}

Describe 'Get-ProcessName' {
    It 'strips .exe and lowercases' {
        Get-ProcessName 'Chrome.exe' | Should -Be 'chrome'
    }
    It 'handles no-extension names' {
        Get-ProcessName 'WezTerm' | Should -Be 'wezterm'
    }
    It 'is case-insensitive' {
        Get-ProcessName 'CHROME.EXE' | Should -Be 'chrome'
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `powershell.exe -Command "Invoke-Pester -Path $REPO/config/skills/screenshot/tests/capture.Tests.ps1"`
Expected: 6 new failures.

- [ ] **Step 3: Implement both helpers**

```powershell
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
```

- [ ] **Step 4: Run tests — expect PASS**

Expected: all 6 tests pass. Existing Task 1 tests still pass.

- [ ] **Step 5: Checkpoint.**

---

## Task 4: Helper — `Apply-Region` (pure, TDD)

**Files:**
- Modify: `capture.ps1` (add helper)
- Modify: `capture.Tests.ps1` (add tests)

- [ ] **Step 1: Write failing tests**

```powershell
Describe 'Apply-Region' {
    $bounds = @{
        ExtendedFrame = @{ Left=100; Top=50; Right=900; Bottom=650 }  # 800x600
        ClientRect    = @{ Left=108; Top=80; Right=892; Bottom=642 }  # title bar ~30px
    }

    It 'returns extended frame for full' {
        $r = Apply-Region -Bounds $bounds -Region 'full'
        $r.Left | Should -Be 100; $r.Top | Should -Be 50
        $r.Right | Should -Be 900; $r.Bottom | Should -Be 650
    }
    It 'returns client rect for content' {
        $r = Apply-Region -Bounds $bounds -Region 'content'
        $r.Left | Should -Be 108; $r.Top | Should -Be 80
    }
    It 'returns title bar strip for titlebar' {
        $r = Apply-Region -Bounds $bounds -Region 'titlebar'
        $r.Left | Should -Be 100; $r.Top | Should -Be 50
        $r.Right | Should -Be 900; $r.Bottom | Should -Be 80  # ClientRect.Top
    }
    It 'splits left-half correctly' {
        $r = Apply-Region -Bounds $bounds -Region 'left-half'
        $r.Left | Should -Be 100; $r.Right | Should -Be 500  # midpoint
    }
    It 'splits right-half correctly' {
        $r = Apply-Region -Bounds $bounds -Region 'right-half'
        $r.Left | Should -Be 500; $r.Right | Should -Be 900
    }
    It 'returns center as middle 50%' {
        $r = Apply-Region -Bounds $bounds -Region 'center'
        # 25% = 100 + 200 = 300; 75% = 100 + 600 = 700
        $r.Left | Should -Be 300; $r.Right | Should -Be 700
        $r.Top | Should -Be 200;  $r.Bottom | Should -Be 500
    }
    It 'returns top 5% strip for top-strip' {
        $r = Apply-Region -Bounds $bounds -Region 'top-strip'
        $r.Top | Should -Be 50; $r.Bottom | Should -Be 80  # 50 + 30
    }
    It 'throws on unknown region' {
        { Apply-Region -Bounds $bounds -Region 'bogus' } | Should -Throw
    }
}
```

- [ ] **Step 2: Run — expect FAIL (8 failures).**

- [ ] **Step 3: Implement `Apply-Region`.** Pure math on the hashtable bounds. Use integer division consistent with the test expectations (PowerShell `[int]` truncates toward zero; halves use `[int](($L + $R) / 2)`).

- [ ] **Step 4: Run — expect PASS.**

- [ ] **Step 5: Checkpoint.**

---

## Task 5: Helper — `Test-CaptureBlank` (pure, TDD with synthetic bitmaps)

**Files:**
- Modify: `capture.ps1` (add helper)
- Modify: `capture.Tests.ps1` (add tests)

- [ ] **Step 1: Write failing tests using synthesized `System.Drawing.Bitmap`**

```powershell
Describe 'Test-CaptureBlank' {
    function New-SolidBitmap { param([int]$W, [int]$H, [System.Drawing.Color]$Color)
        $bmp = New-Object System.Drawing.Bitmap($W,$H)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.Clear($Color); $g.Dispose()
        $bmp
    }

    It 'flags all-black 800x600 bitmap as blank' {
        $bmp = New-SolidBitmap 800 600 ([System.Drawing.Color]::Black)
        (Test-CaptureBlank -Bitmap $bmp).IsBlank | Should -BeTrue
        $bmp.Dispose()
    }
    It 'flags all-white 800x600 as blank (uniform color)' {
        $bmp = New-SolidBitmap 800 600 ([System.Drawing.Color]::White)
        (Test-CaptureBlank -Bitmap $bmp).IsBlank | Should -BeTrue
        $bmp.Dispose()
    }
    It 'does NOT flag small 150x150 uniform bitmap (under min size)' {
        $bmp = New-SolidBitmap 150 150 ([System.Drawing.Color]::Gray)
        (Test-CaptureBlank -Bitmap $bmp).IsBlank | Should -BeFalse
        $bmp.Dispose()
    }
    It 'does NOT flag a bitmap with gradient content' {
        $bmp = New-Object System.Drawing.Bitmap(800,600)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.Point(0,0)),
            (New-Object System.Drawing.Point(800,600)),
            [System.Drawing.Color]::Red, [System.Drawing.Color]::Blue)
        $g.FillRectangle($brush, 0, 0, 800, 600)
        $g.Dispose()
        (Test-CaptureBlank -Bitmap $bmp).IsBlank | Should -BeFalse
        $bmp.Dispose()
    }
    It 'reports CenterBlack count correctly' {
        $bmp = New-SolidBitmap 800 600 ([System.Drawing.Color]::Black)
        (Test-CaptureBlank -Bitmap $bmp).CenterBlack | Should -Be 9
        $bmp.Dispose()
    }
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement `Test-CaptureBlank`.**

Sample points:
- 5×5 grid: `(W*i/5 + W/10, H*j/5 + H/10)` for i,j in 0..4 → 25 samples
- Center cluster: 3×3 in middle 30% (`W*0.35` to `W*0.65`, step `W*0.15`) → 9 samples
- For each, read `GetPixel`, compute `R+G+B`

Check logic:
- Skip uniform-color check if `$W -lt 200 -or $H -lt 200`
- Return hashtable: `@{ IsBlank = $bool; CenterBlack = $N; OverallBlack = $N; StdDev = $D }`

Thresholds exactly per spec Section 5.

- [ ] **Step 4: Run — expect PASS.**

- [ ] **Step 5: Checkpoint.**

---

## Task 6: Helper — `Get-WindowBounds` (P/Invoke, smoke-tested)

**Files:**
- Modify: `capture.ps1` (add helper)
- Modify: `capture.Tests.ps1` (add smoke test)

- [ ] **Step 1: Write smoke test (not strict unit test — bounds vary per run)**

```powershell
Describe 'Get-WindowBounds (smoke)' {
    It 'returns a plausible structure for foreground window' {
        $hwnd = [Win32]::GetForegroundWindow()
        $b = Get-WindowBounds -Hwnd $hwnd
        $b.ExtendedFrame.Right | Should -BeGreaterThan $b.ExtendedFrame.Left
        $b.ClientRect.Right | Should -BeGreaterThan $b.ClientRect.Left
        $b.Dpi | Should -BeGreaterOrEqual 96
        $b.IsMinimized | Should -BeOfType [bool]
    }
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement `Get-WindowBounds`.**

Call in order:
1. `IsIconic` for `IsMinimized`
2. `IsWindowVisible`
3. `DwmGetWindowAttribute` with attr 9 → `ExtendedFrame`; if HRESULT < 0, fall back to `GetWindowRect`
4. `GetWindowRect` → `WindowRect`
5. `GetClientRect` → client (window-local)
6. `ClientToScreen` on top-left of client rect, add client width/height → screen-space `ClientRect`
7. `MonitorFromWindow(MONITOR_DEFAULTTONEAREST=2)` → monitor handle; convert to index by enumerating `[System.Windows.Forms.Screen]::AllScreens` and matching on handle (wrap in try/catch — fall back to 0 on mismatch)
8. `GetDpiForWindow` inside try/catch → default 96 on failure
9. `GetForegroundWindow` == hWnd → `IsForeground`
10. Z-order via walking `GetWindow(hWnd, GW_HWNDPREV=3)` up to the top — count steps for `ZOrder` (0 = topmost)

Return as nested hashtable matching the spec schema.

- [ ] **Step 4: Run — expect PASS.**

- [ ] **Step 5: Checkpoint.**

---

## Task 7: Helper — `Capture-Window` with strategy fallback

**Files:**
- Modify: `capture.ps1` (add helper)
- Modify: `capture.Tests.ps1` (smoke test only)

- [ ] **Step 1: Write smoke test**

```powershell
Describe 'Capture-Window (smoke)' {
    It 'captures the current foreground window with auto strategy' {
        $hwnd = [Win32]::GetForegroundWindow()
        $result = Capture-Window -Hwnd $hwnd -Strategy 'auto'
        $result.Bitmap | Should -Not -BeNullOrEmpty
        $result.Bitmap.Width | Should -BeGreaterThan 0
        $result.Strategy | Should -BeIn @('printwindow','restore')
        $result.Bitmap.Dispose()
    }
}
```

- [ ] **Step 2: Run — FAIL.**

- [ ] **Step 3: Implement `Capture-Window`.**

Structure:
```powershell
function Capture-Window {
    param([IntPtr]$Hwnd, [string]$Strategy = 'auto')
    $bounds = Get-WindowBounds -Hwnd $Hwnd
    $procName = Get-ProcessName (Get-Process -Id (Get-PidForHwnd $Hwnd)).ProcessName

    $useStrategy = $Strategy
    if ($useStrategy -eq 'auto') {
        if ($PROBLEMATIC_PROCS -contains $procName) { $useStrategy = 'restore' }
    }

    if ($useStrategy -in @('auto','printwindow')) {
        $bmp = Invoke-PrintWindow -Hwnd $Hwnd -Bounds $bounds
        $blank = Test-CaptureBlank -Bitmap $bmp
        if (-not $blank.IsBlank) {
            return @{ Bitmap=$bmp; Strategy='printwindow'; Bounds=$bounds; BlankInfo=$blank }
        }
        if ($Strategy -eq 'printwindow') {
            throw "capture_failed|pw_blank=yes|center_black=$($blank.CenterBlack)/9|overall_black=$($blank.OverallBlack)/25"
        }
        $bmp.Dispose()
    }

    # restore strategy
    $wasMinimized = $bounds.IsMinimized
    if ($wasMinimized) { [Win32]::ShowWindow($Hwnd, 4) | Out-Null; Start-Sleep -Milliseconds 150 }
    $fresh = Get-WindowBounds -Hwnd $Hwnd
    $bmp = Invoke-ScreenCopy -Bounds $fresh.ExtendedFrame
    if ($wasMinimized) { [Win32]::ShowWindow($Hwnd, 6) | Out-Null }
    @{ Bitmap=$bmp; Strategy='restore'; Bounds=$fresh; BlankInfo=$null }
}
```

Plus two small helpers:
- `Invoke-PrintWindow` — create bitmap sized to `ExtendedFrame`, Graphics from it, get HDC, call `PrintWindow(hwnd, hdc, 2)`, release HDC, return bitmap
- `Invoke-ScreenCopy` — `CopyFromScreen` using the bounds rect (same as existing overview code but parametrized)
- `Get-PidForHwnd` — wraps `GetWindowThreadProcessId`

- [ ] **Step 4: Run — PASS.**

- [ ] **Step 5: Manual smoke: spec Testing item #5**

Open Chrome, run from WSL:
```
powershell.exe -Command ". '$(wslpath -w ~/.claude/skills/screenshot/capture.ps1)' -DotSourceOnly; \$h = [Win32]::GetForegroundWindow(); \$r = Capture-Window -Hwnd \$h -Strategy auto; Write-Host \$r.Strategy"
```
Expected: prints `restore` (Chrome is problematic).

- [ ] **Step 6: Checkpoint.**

---

## Task 8: Helper — `Resolve-Window` with tiered auto-resolution

**Files:**
- Modify: `capture.ps1` (add helper)
- Modify: `capture.Tests.ps1` (add ranking unit test)

- [ ] **Step 1: Write failing test for the pure ranking sub-function**

Split ranking into its own pure helper `Get-CandidateRanking` that takes an array of candidate hashtables and returns them sorted. Test it in isolation:

```powershell
Describe 'Get-CandidateRanking' {
    It 'ranks foreground above others' {
        $cands = @(
            @{ Hwnd=1; IsForeground=$false; ZOrder=0; IsMinimized=$false; Area=1000 },
            @{ Hwnd=2; IsForeground=$true;  ZOrder=5; IsMinimized=$false; Area=500 }
        )
        (Get-CandidateRanking $cands)[0].Hwnd | Should -Be 2
    }
    It 'puts minimized last' {
        $cands = @(
            @{ Hwnd=1; IsForeground=$false; ZOrder=0; IsMinimized=$true;  Area=1000 },
            @{ Hwnd=2; IsForeground=$false; ZOrder=1; IsMinimized=$false; Area=500 }
        )
        (Get-CandidateRanking $cands)[0].Hwnd | Should -Be 2
    }
    It 'breaks ties by area (larger wins)' {
        $cands = @(
            @{ Hwnd=1; IsForeground=$false; ZOrder=0; IsMinimized=$false; Area=500 },
            @{ Hwnd=2; IsForeground=$false; ZOrder=0; IsMinimized=$false; Area=1000 }
        )
        (Get-CandidateRanking $cands)[0].Hwnd | Should -Be 2
    }
}
```

- [ ] **Step 2: Run — FAIL.**

- [ ] **Step 3: Implement `Get-CandidateRanking` and `Resolve-Window`.**

`Get-CandidateRanking`: `Sort-Object` with a composite key — foreground first (sort desc on bool), then `IsMinimized` asc (false before true), then `ZOrder` asc (topmost first), then `Area` desc.

`Resolve-Window`:
1. If `-Hwnd` provided → validate handle is a window (call `IsWindowVisible` OR `IsIconic` — error `no_match` if neither)
2. If `-Pid` provided → enumerate all top-level windows whose PID matches; exactly 1 → use it, else gather as candidates
3. If `-WindowTitle` → enumerate visible + minimized top-level windows, collect title for each via `GetWindowText`, substring-match (case-insensitive). Track exact-title matches separately.
4. Apply resolution tiers from spec Section "Resolve-Window"
5. Return single HWND OR `@{ Ambiguous = $true; Candidates = $sortedArray }`

Returns a structure; the mode dispatcher decides how to emit it.

- [ ] **Step 4: Run — ranking tests PASS.**

- [ ] **Step 5: Smoke for end-to-end resolution**

Run with the current foreground window's partial title:
```
powershell.exe -File capture.ps1 -DotSourceOnly
# then in same shell: $r = Resolve-Window -WindowTitle 'some unique substring'
```
Verify: single HWND when unique; ambiguous structure when not.

- [ ] **Step 6: Checkpoint.**

---

## Task 9: Mode — `list-windows`

**Files:**
- Modify: `capture.ps1` (add mode to `ValidateSet`, add dispatch case)

- [ ] **Step 1: Add `list-windows` to `ValidateSet` and add a `-Filter <regex>` param**

- [ ] **Step 2: Implement dispatch**

```powershell
elseif ($Mode -eq 'list-windows') {
    $windows = @()
    # IMPORTANT: cast the script block to the exact delegate type Add-Type generated
    # (Win32+EnumWindowsProc). Without the cast, P/Invoke marshalling fails at runtime
    # with an opaque type-coercion error.
    [Win32+EnumWindowsProc]$callback = {
        param($hwnd, $lparam)
        if (-not ([Win32]::IsWindowVisible($hwnd) -or [Win32]::IsIconic($hwnd))) { return $true }
        $len = [Win32]::GetWindowTextLength($hwnd)
        if ($len -eq 0) { return $true }
        $sb = New-Object System.Text.StringBuilder($len + 1)
        [Win32]::GetWindowText($hwnd, $sb, $sb.Capacity) | Out-Null
        $title = $sb.ToString()
        if ($Filter -and $title -notmatch $Filter) { return $true }
        $pid_ = 0
        [Win32]::GetWindowThreadProcessId($hwnd, [ref]$pid_) | Out-Null
        $proc = try { (Get-Process -Id $pid_).ProcessName } catch { 'unknown' }
        $b = Get-WindowBounds -Hwnd $hwnd
        $script:windows += [pscustomobject]@{ Hwnd=$hwnd; Pid=$pid_; Proc=(Get-ProcessName $proc); Title=$title; Bounds=$b }
        return $true
    }
    [Win32]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null

    # Emit count header
    Write-Result -Kind 'windows' -Payload ([ordered]@{ count = $windows.Count }) -Format $Format

    # Emit rows (ordered: visible foreground first, then visible, then minimized)
    $sorted = $windows | Sort-Object @{E={-not $_.Bounds.IsForeground}},@{E={$_.Bounds.IsMinimized}},@{E={$_.Title}}
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
```

- [ ] **Step 3: Smoke — spec Testing item #2**

Run: `powershell.exe -File capture.ps1 -Mode list-windows`
Expected: header line `windows|<N>` then N rows. Current terminal should have `focus=yes`.

Run with filter: `... -Mode list-windows -Filter 'Chrome|Firefox'`
Expected: only browser entries.

- [ ] **Step 4: JSON smoke**

Run: `... -Mode list-windows -Format json | jq .`
Expected: valid JSON, one object per line (jq handles NDJSON with appropriate flag if needed — verify format matches spec).

- [ ] **Step 5: Checkpoint.**

---

## Task 10: Mode — `window`

**Files:**
- Modify: `capture.ps1` (add mode, params, dispatch)

- [ ] **Step 1: Add mode to `ValidateSet` and new params**

Add to `param()`:
```powershell
# NOTE: $Pid is a PowerShell automatic variable (current process ID).
# We expose -Pid as the flag name but bind it to $TargetPid internally.
[Parameter()][Alias('Pid')][int]$TargetPid,
[IntPtr]$Hwnd = [IntPtr]::Zero,
[string]$WindowTitle,
[ValidateSet('full','content','titlebar','left-half','right-half','top-half','bottom-half','center','top-strip')]
[string]$Region = 'full',
[ValidateSet('auto','printwindow','restore')]
[string]$Strategy = 'auto',
[switch]$Best,
[switch]$First
```

- [ ] **Step 2: Implement dispatch**

```powershell
elseif ($Mode -eq 'window') {
    $resolved = Resolve-Window -WindowTitle $WindowTitle -TargetPid $TargetPid -Hwnd $Hwnd -Best:$Best -First:$First
    if ($resolved.Ambiguous) {
        Write-Result -Kind 'error' -Payload ([ordered]@{ reason='ambiguous'; matches=$resolved.Candidates.Count }) -Format $Format
        foreach ($c in $resolved.Candidates) { Write-Result -Kind 'window' -Payload (...) -Format $Format }
        exit 2
    }
    if ($resolved.NoMatch) {
        Write-Result -Kind 'error' -Payload ([ordered]@{ reason='no_match' }) -Format $Format
        exit 1
    }

    $captureId = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    try {
        $cap = Capture-Window -Hwnd $resolved.Hwnd -Strategy $Strategy
    } catch {
        Write-Result -Kind 'error' -Payload ([ordered]@{ reason='capture_failed'; hwnd=$resolved.Hwnd; detail="$_" }) -Format $Format
        exit 3
    }

    # Crop to region
    $region = Apply-Region -Bounds $cap.Bounds -Region $Region
    # Translate region screen coords to bitmap-local coords (subtract ExtendedFrame.Left/Top)
    $lx = $region.Left - $cap.Bounds.ExtendedFrame.Left
    $ly = $region.Top  - $cap.Bounds.ExtendedFrame.Top
    $lw = $region.Right - $region.Left
    $lh = $region.Bottom - $region.Top
    $cropRect = New-Object System.Drawing.Rectangle($lx, $ly, $lw, $lh)
    $cropped = ([System.Drawing.Bitmap]$cap.Bitmap).Clone($cropRect, $cap.Bitmap.PixelFormat)
    $cap.Bitmap.Dispose()

    # Save full-res temp (for window-crop to reuse)
    $tempPath = Join-Path $TEMP_DIR "capture_${captureId}.png"
    $cropped.Save($tempPath)

    # Scale to 1568 long edge
    $scaled = Resize-ToMaxDim -Bitmap $cropped -MaxDim 1568
    $cropped.Dispose()

    $outPath = Join-Path $SCREENSHOT_DIR "Screenshot ${captureId}_window.png"
    $scaled.Save($outPath)

    Write-Result -Kind 'window' -Payload ([ordered]@{
        path = $outPath
        dims = "$($scaled.Width)x$($scaled.Height)"
        capture_id = $captureId
        hwnd = $resolved.Hwnd
        proc = $resolved.Proc
        region = $Region
        strategy = $cap.Strategy
        window_rect = "$($cap.Bounds.ExtendedFrame.Left),$($cap.Bounds.ExtendedFrame.Top),$($cap.Bounds.ExtendedFrame.Right),$($cap.Bounds.ExtendedFrame.Bottom)"
        captured_rect = "$($region.Left),$($region.Top),$($region.Right),$($region.Bottom)"
    }) -Format $Format

    $scaled.Dispose()
}
```

Factor out `Resize-ToMaxDim` and reuse in existing overview/crop.

- [ ] **Step 3: Smoke — spec Testing items #3, #4, #6, #7**

Each smoke test from the spec Testing section. Run one at a time, confirm output and visual image.

- [ ] **Step 4: Checkpoint.**

---

## Task 11: Mode — `window-crop`

**Files:**
- Modify: `capture.ps1` (mode + dispatch)

- [ ] **Step 1: Add mode to `ValidateSet`.**

- [ ] **Step 2: Implement dispatch**

Nearly identical to existing `crop` mode — same `Left/Top/Right/Bottom` percentage math on the temp capture. Only difference: the output kind and filename suffix are `window-crop`. Extract a shared helper `Invoke-PercentCrop -CaptureId -Left -Top -Right -Bottom -Suffix` and call from both `crop` and `window-crop`.

- [ ] **Step 3: Smoke — spec Testing item #9**

Run `window` → capture `$id` → run `window-crop -CaptureId $id -Left 50 -Top 0 -Right 100 -Bottom 50`. Expected: image of top-right quadrant of the window.

- [ ] **Step 4: Backwards-compat re-check**

Run original `crop` against an `overview` capture — still works identically.

- [ ] **Step 5: Checkpoint.**

---

## Task 12: Documentation — update `SKILL.md`

**Files:**
- Modify: `$REPO/config/skills/screenshot/SKILL.md`

- [ ] **Step 1: Add `### Window targeting` subsection under `## Modes`**

Document `list-windows`, `window`, `window-crop` with one example each. Keep concise — match the existing doc's compactness.

- [ ] **Step 2: Add `### Region keywords` table**

| Keyword | Covers |
|---------|--------|
| `full` | Entire window (extended frame) |
| `content` | Client area — excludes title bar, borders |
| `titlebar` | Title bar strip |
| `left-half`, `right-half`, `top-half`, `bottom-half` | Halves of extended frame |
| `center` | Middle 50% box |
| `top-strip` | Fixed top 5% |

- [ ] **Step 3: Add `### Disambiguation` subsection**

Explain `-Best`, `-First`, and the candidate-row fallback.

- [ ] **Step 4: Add `### JSON output` subsection**

Show `-Format json` example and note it applies to every mode.

- [ ] **Step 5: Update Workflow section**

Add line: "When the target app is known, skip `overview` — go straight to `window`."

- [ ] **Step 6: Update Token Budget table** with window-mode numbers from spec.

- [ ] **Step 7: Checkpoint.**

---

## Task 13: End-to-end verification against spec Testing section

**Files:** none (pure verification)

- [ ] **Step 1: Run spec tests 1-10 in order**

Copy the numbered list from `docs/superpowers/specs/2026-04-16-smart-screenshots-design.md` → `## Testing`. Execute each; for each, record: PASS/FAIL, any notes.

- [ ] **Step 2: If any fail**, diagnose root cause, fix, re-run full checklist. Do NOT mark this task complete with failing spec tests.

- [ ] **Step 3: Re-run full Pester suite**

Run: `powershell.exe -Command "Invoke-Pester -Path $REPO/config/skills/screenshot/tests/ -Output Detailed"`
Expected: all unit tests still pass.

- [ ] **Step 4: Checkpoint — feature complete on live machine.**

---

## Task 14: Capture changelog entry for other machines

Covers TWO things in one changelog:
1. The one-time migration of the screenshot skill from `~/.claude/skills/` into the repo + symlink setup (so other machines can adopt the same layout)
2. The new window-targeting features

**Files:**
- Create: `$REPO/changelogs/CHANGELOG-2026-04-16-smart-screenshots.md`
- Modify: `$REPO/CHANGELOG-SUMMARY.md` (append entry at bottom)
- Modify: `$REPO/.changelog-status` (add this filename)

- [ ] **Step 1: Write the changelog per `CLAUDE.md` format**

Required fields: Date, Tag (`[core]`), Summary, Goal, Change, Deployment, Verification.

**Deployment section** must walk a new machine through:
```bash
# SAFETY: verify ~/.claude/skills/screenshot is a real directory (not already a symlink)
# before moving. If it's already a symlink, just replace the target.
if [ -L ~/.claude/skills/screenshot ]; then
    rm ~/.claude/skills/screenshot
elif [ -d ~/.claude/skills/screenshot ]; then
    mv ~/.claude/skills/screenshot ~/.claude/skills/screenshot.bak
fi
# Create symlink to the repo (adjust REPO_PATH for this machine):
ln -s <REPO_PATH>/config/skills/screenshot ~/.claude/skills/screenshot
```

Note `<REPO_PATH>` as a `<!-- edit per machine: repo clone path -->` marker per `CLAUDE.md` convention.

**Verification section** references the spec's Testing checklist — paste the 10 items verbatim or link to the spec file.

- [ ] **Step 2: Append entry to `CHANGELOG-SUMMARY.md`** — one line at the bottom following existing format.

- [ ] **Step 3: Add filename to `.changelog-status`** on this machine (this machine has already applied the change).

- [ ] **Step 4: Ask the user whether to `git commit`** the changelog files (never commit without explicit ask per `CLAUDE.md`).

---

## Task Tail: Commit Cadence Summary

Every task from 0–13 ends with a `git commit` in `$REPO`. Task 14's commit is deferred pending explicit user approval (commit-hygiene rule from `CLAUDE.md`). Commit messages follow the repo's existing `feat:` / `chore:` / `docs:` conventions — check `git log` on the repo for current style.

---

## Verification Complete

After Task 14, confirm all boxes are checked. The feature is:
- ✅ Live on this machine (via symlink at `~/.claude/skills/screenshot`)
- ✅ Version-controlled in `$REPO/config/skills/screenshot/`
- ✅ Captured in this repo's changelogs for other machines to adopt
- ✅ Unit-tested for pure logic, smoke-tested for Win32 paths
- ✅ Backwards compatible (existing `overview`/`crop`/`list` unchanged from user's perspective)

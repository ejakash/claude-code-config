# Screenshot Skill v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship v2 of the screenshot skill: raise-without-focus capture correctness, shutter+overlay user confirmation, and all 24 audit fixes from the 2026-04-17 audit.

**Architecture:** Single-file PowerShell script (`capture.ps1`) extended with new Win32 P/Invoke imports (`SetWindowPos`, `GetWindow`), an inline WPF overlay helper, and a bundled `.wav` asset. The `restore` strategy is rewritten as raise-without-focus: un-minimize if needed, `SetWindowPos(HWND_TOP, SWP_NOACTIVATE)`, show overlay + play shutter, hide overlay, read pixels, restore prior Z-order in `finally`. All other fixes are in-place edits to existing functions.

**Tech Stack:** PowerShell 5.1/7, Win32 P/Invoke (user32.dll, dwmapi.dll), WPF (PresentationFramework), GDI+ (System.Drawing), System.Media.SoundPlayer, Pester 5.

**Spec:** `docs/superpowers/specs/2026-04-17-screenshot-v2-design.md`

---

## Audit-fix coverage matrix

Each entry in the 2026-04-17 audit maps to a task below. Every task that commits audit-fix code should reference the fix ID in its commit message (e.g. `(audit #12)`).

| # | Fix (from spec §3) | Task |
|---|---|---|
| 1 | `-Hwnd` alias + `[long]` type | A1 |
| 2 | `-CaptureId` path-traversal validation | A2 |
| 3 | `-Left/-Top/-Right/-Bottom` range validation | A2 |
| 4 | Remove `-First` switch | A2 |
| 5 | `-Filter` regex timeout (ReDoS) | C1 |
| 6 | `$SCREENSHOT_DIR` → `LOCALAPPDATA` + env override | C2 |
| 7 | Sanitize `-Proc` / exception detail | C3 |
| 8 | `restore` try/finally | F1 (incorporated) |
| 9 | `DwmGetWindowAttribute` try/catch | D1 |
| 10 | Bitmap dim validation | D2 |
| 11 | Clamp `crop` percentages | D3 |
| 12 | `FromFile` try/finally | D4 |
| 13 | `[GC]::KeepAlive` EnumWindows | D5 |
| 14 | `CreationTime` temp purge | D6 |
| 15 | `SCREENSHOT_DIR` auto-create | C2 |
| 16 | `auto_resolved` single-field | B3 |
| 17 | UTF-8 console encoding | B1 |
| 18 | Underscore filenames | B3 |
| 19 | Drop `last_active` field | B3 |
| 20 | `Capture-Window` → `Invoke-WindowCapture` | H1 |
| 21 | `Apply-Region` → `Resolve-RegionRect` | H1 |
| 22 | `Write-Host` → `Write-Output` in `Write-Result` | B2 |
| 23 | Hoist magic numbers to constants | E1 |
| 24 | SKILL.md doc fixes | J1 |

**Plus** the correctness rewrite (spec §1, F1/G4) and the overlay+shutter feature (§2, G1–G4) which are not audit-derived but are the primary goal of v2.

---

## File Structure

**Modified:**
- `config/skills/screenshot/capture.ps1` — all code changes (~1100 lines after changes)
- `config/skills/screenshot/SKILL.md` — docs updates (§3.6 of spec)
- `config/skills/screenshot/tests/capture.Tests.ps1` — new test cases + renames

**Created:**
- `config/skills/screenshot/assets/shutter.wav` — short shutter-click asset (<20 KB, CC0/PD)
- `config/skills/screenshot/assets/README.md` — asset provenance + license note
- `changelogs/CHANGELOG-2026-04-17-screenshot-v2.md` — changelog entry per `CLAUDE.md` format

---

## Task Organization

Tasks are ordered by risk and dependency: pure parameter/validation edits first (lowest blast radius), then security and robustness, then Win32 additions (prerequisite for raise-without-focus), then the behavioural changes (capture correctness, overlay, shutter), then renames, then docs. Commit after each task. No task should take longer than ~5 minutes of focused work.

---

## Section A — Parameter surface (spec §3.1)

### Task A1: Add `-Hwnd` alias and change `$WindowHwnd` type to `[long]`

**Files:**
- Modify: `config/skills/screenshot/capture.ps1:22`
- Test: `config/skills/screenshot/tests/capture.Tests.ps1` (new Describe block)

- [ ] **Step 1: Write the failing test**

Append to `tests/capture.Tests.ps1`:

```powershell
Describe 'Parameter surface — WindowHwnd' {
    It 'binds -Hwnd alias to WindowHwnd' {
        $params = (Get-Command $script:CapturePath).Parameters
        $params.ContainsKey('WindowHwnd') | Should -BeTrue
        $params['WindowHwnd'].Aliases | Should -Contain 'Hwnd'
    }
    It 'accepts an integer string from the command line' {
        # [long] accepts '526098'; [IntPtr] rejects it.
        $params = (Get-Command $script:CapturePath).Parameters
        $params['WindowHwnd'].ParameterType.FullName | Should -Be 'System.Int64'
    }
    It 'round-trips hwnd= from list-windows through -Hwnd' {
        # Shell out so we exercise real parameter binding, not the in-process Pester metadata.
        # An invalid hwnd still binds — we assert NO "Cannot bind parameter" error appears.
        $out = powershell.exe -NoProfile -Command "& '$script:CapturePath' -Mode window -Hwnd 526098 -Format pipe 2>&1"
        ($out -join "`n") | Should -Not -Match 'Cannot bind parameter'
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (Windows PowerShell):
```
pwsh.exe -NoProfile -Command "Invoke-Pester -Path 'config\skills\screenshot\tests\capture.Tests.ps1' -Output Detailed"
```
Expected: FAIL — two assertions fail (no `Hwnd` alias, type is `IntPtr`).

- [ ] **Step 3: Implement**

Edit `capture.ps1:22`:

```powershell
    [Parameter()][Alias('Hwnd')][long]$WindowHwnd = 0,
```

Where `$WindowHwnd` is converted to `IntPtr` at use sites. Update all downstream usages:
- `capture.ps1:548`: `if ($Hwnd -ne [IntPtr]::Zero)` → change parameter type of `Resolve-Window` to `[long]$Hwnd = 0` and use `[IntPtr]::new($Hwnd)` where needed, **OR** (preferred) convert at caller site: `capture.ps1:829` passes `-Hwnd $WindowHwnd`; change to `-Hwnd ([IntPtr]::new($WindowHwnd))` and keep `Resolve-Window` signature `[IntPtr]`.

Preferred: convert at the boundary. At `capture.ps1:829`:

```powershell
    $resolved = Resolve-Window -WindowTitle $WindowTitle -TargetPid $TargetPid `
        -Hwnd ([IntPtr]::new($WindowHwnd)) -Proc $Proc -Best:$Best
```

- [ ] **Step 4: Run test to verify it passes**

Same Pester command. Expected: PASS.

- [ ] **Step 5: Commit**

```
git add config/skills/screenshot/capture.ps1 config/skills/screenshot/tests/capture.Tests.ps1
git commit -m "fix(screenshot): add -Hwnd alias; bind WindowHwnd as [long] for CLI round-trip"
```

---

### Task A2: Validate `-CaptureId`, `-Left/-Top/-Right/-Bottom`, drop `-First`

**Files:**
- Modify: `config/skills/screenshot/capture.ps1:7-13`, `:31-32`
- Test: `config/skills/screenshot/tests/capture.Tests.ps1`

- [ ] **Step 1: Write failing tests**

Append to `tests/capture.Tests.ps1`:

```powershell
Describe 'Parameter surface — validation' {
    It 'rejects CaptureId with path traversal' {
        $cmd = "& '$script:CapturePath' -Mode crop -CaptureId '..\..\etc' 2>&1"
        $out = powershell.exe -NoProfile -Command $cmd
        $LASTEXITCODE | Should -Not -Be 0
        ($out -join "`n") | Should -Match 'ValidatePattern|parameter'
    }
    It 'rejects Left=150 as out of range' {
        $cmd = "& '$script:CapturePath' -Mode crop -CaptureId '20260417_120000_000' -Left 150 2>&1"
        $out = powershell.exe -NoProfile -Command $cmd
        $LASTEXITCODE | Should -Not -Be 0
    }
    It 'no longer exposes -First switch' {
        $params = (Get-Command $script:CapturePath).Parameters
        $params.ContainsKey('First') | Should -BeFalse
    }
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

Edit `capture.ps1:7-13`:

```powershell
    # For crop mode: which capture to zoom into.
    # Pattern matches the yyyyMMdd_HHmmss_fff timestamps we emit; blocks traversal.
    [ValidatePattern('^\d{8}_\d{6}_\d{3}$|^$')]
    [string]$CaptureId,

    # Crop region as percentages (0-100) of the full image
    [ValidateRange(0,100)][float]$Left = 0,
    [ValidateRange(0,100)][float]$Top = 0,
    [ValidateRange(0,100)][float]$Right = 100,
    [ValidateRange(0,100)][float]$Bottom = 100,
```

Edit `capture.ps1:31-32` — delete the `[switch]$First` line. Remove all `-First` references from `Resolve-Window`, `Resolve-Ambiguity`, and the `window`-mode caller.

`Resolve-Ambiguity` body becomes:

```powershell
function Resolve-Ambiguity {
    param([array]$Matches, [switch]$Best)
    $sorted = Get-CandidateRanking -Candidates $Matches
    if ($Best) {
        $m = @($sorted)[0]
        return @{ Hwnd = $m.Hwnd; Proc = $m.Proc; AutoResolved = 'best' }
    }
    return @{ Ambiguous = $true; Candidates = @($sorted) }
}
```

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```
git add config/skills/screenshot/capture.ps1 config/skills/screenshot/tests/capture.Tests.ps1
git commit -m "fix(screenshot): validate CaptureId path + percent ranges; drop unused -First"
```

---

## Section B — Output format (spec §3.4)

### Task B1: UTF-8 console output

**Files:** Modify `capture.ps1` (top of script, after `Add-Type`)

- [ ] **Step 1: Write failing test**

PowerShell 7 defaults to UTF-8 already, so asserting `OutputEncoding` live gives a false pass on PS 7. Assert against the script source instead — the test then fails meaningfully on both PS 5.1 and 7 until the assignment is added.

```powershell
Describe 'Output encoding' {
    It 'script sets Console OutputEncoding to UTF-8 near the top' {
        $src = Get-Content $script:CapturePath -Raw
        $src | Should -Match '\[Console\]::OutputEncoding\s*=\s*\[System\.Text\.UTF8Encoding\]::new\(\)'
    }
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement** — after `Add-Type -AssemblyName System.Windows.Forms,System.Drawing` (line 118):

```powershell
# Non-ASCII titles (®, ©, emoji) get mangled to '?' without this.
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```
git commit -m "fix(screenshot): set UTF-8 console encoding for non-ASCII window titles"
```

---

### Task B2: `Write-Output` instead of `Write-Host`; drop `6>&1` in tests

**Files:** `capture.ps1:137,146`; `tests/capture.Tests.ps1` (find-and-replace)

- [ ] **Step 1: Edit tests** — remove `6>&1` from every `Write-Result` invocation in the test file. After edit, tests will fail against current `Write-Host` impl (stream 6 is information, 1 is output). Also add a new spec that asserts JSON parses from stdout:

```powershell
It 'emits valid JSON on stdout with -Format json' {
    $out = Write-Result -Kind 'overview' -Payload ([ordered]@{ path = 'C:\x.png' }) -Format 'json'
    { $out | ConvertFrom-Json } | Should -Not -Throw
}
```

Run tests — expect FAIL on existing Write-Result specs.

- [ ] **Step 2: Implement**

Edit `capture.ps1:137`:
```powershell
        $obj | ConvertTo-Json -Compress -Depth 5 | Write-Output
```

Edit `capture.ps1:146`:
```powershell
    Write-Output ($parts -join '|')
```

- [ ] **Step 3: Run tests — expect PASS**

- [ ] **Step 4: Commit**

```
git commit -m "fix(screenshot): emit on stdout (Write-Output) not info stream"
```

---

### Task B3: Rename output filenames; collapse `auto_resolved`; drop `last_active`

**Files:** `capture.ps1:704, 764, 918, 934, 847, 986`

- [ ] **Step 1: Write failing tests**

Append:

```powershell
Describe 'Output format' {
    It 'filenames use underscores not spaces' {
        Select-String -Path $script:CapturePath -Pattern 'Screenshot \$\{' -SimpleMatch | Should -BeNullOrEmpty
    }
    It 'auto_resolved field is single value, not yes|<reason>' {
        Select-String -Path $script:CapturePath -Pattern "auto_resolved.*=.*'yes\|" | Should -BeNullOrEmpty
    }
    It 'no longer emits last_active field' {
        Select-String -Path $script:CapturePath -Pattern 'last_active' | Should -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

In `capture.ps1`, four filename edits (replace space with underscore):
- `:704` → `"Screenshot_${captureId}.png"`
- `:764` → `"Screenshot_${CaptureId}_crop.png"`
- `:918` → `"Screenshot_${captureId}_window.png"`
- `:986` → `"Screenshot_${CaptureId}_window_crop.png"`

At `:934`:
```powershell
    if ($resolved.AutoResolved) {
        $payload['auto_resolved'] = $resolved.AutoResolved
    }
```

At `:847` (and the row-emit loop): drop `last_active = $c.LastActive` line and remove `LastActive = 0` from candidate hashtables in `Resolve-Window` (`:576`).

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```
git commit -m "fix(screenshot): underscore filenames; single-field auto_resolved; drop last_active"
```

---

## Section C — Security (spec §3.2)

### Task C1: `-Filter` regex timeout

**Files:** `capture.ps1:786, 793`

- [ ] **Step 1: Write failing test**

Test both the timeout contract AND the integration point (source must compile `$Filter` with `MatchTimeout`). The source assertion fails pre-implementation.

```powershell
Describe 'Security — Filter regex timeout' {
    It 'source compiles Filter with a MatchTimeout' {
        $src = Get-Content $script:CapturePath -Raw
        $src | Should -Match '\[regex\]::new\(\s*\$Filter[\s\S]*?FromMilliseconds'
    }
    It 'a 200ms-timeout regex aborts on pathological input' {
        $title = ('a' * 30) + 'X'
        $rx = [regex]::new('(a+)+b', 'IgnoreCase', [TimeSpan]::FromMilliseconds(200))
        { $rx.IsMatch($title) } | Should -Throw -ExceptionType ([System.Text.RegularExpressions.RegexMatchTimeoutException])
    }
}
```

- [ ] **Step 2: Run — expect FAIL** on the source-assertion spec.

- [ ] **Step 3: Implement in capture.ps1**

Edit the `list-windows` callback. Replace the closure `$script:_filter = $Filter` form with a compiled regex:

At `:793`, where `$script:_filter = $Filter` is set:
```powershell
    $script:_filter = if ($Filter) {
        [regex]::new($Filter, 'IgnoreCase', [TimeSpan]::FromMilliseconds(200))
    } else { $null }
```

At `:786`, change the title check:
```powershell
        if ($script:_filter) {
            try { if (-not $script:_filter.IsMatch($title)) { return $true } }
            catch [System.Text.RegularExpressions.RegexMatchTimeoutException] { return $true }
        }
```

- [ ] **Step 4: Run full Pester — expect PASS**

- [ ] **Step 5: Commit**

```
git commit -m "security(screenshot): compile -Filter with 200ms MatchTimeout (ReDoS mitigation)"
```

---

### Task C2: Move `$SCREENSHOT_DIR` to `$env:LOCALAPPDATA\claude-screenshots` with override

**Files:** `capture.ps1:122-124`

- [ ] **Step 1: Write failing test**

```powershell
Describe 'Screenshot dir' {
    It 'defaults to LOCALAPPDATA\claude-screenshots' {
        # SCREENSHOT_DIR is script-scoped after dot-source.
        $script:SCREENSHOT_DIR | Should -Match 'claude-screenshots$'
        $script:SCREENSHOT_DIR | Should -Not -Match 'Pictures'
    }
    It 'honours CLAUDE_SCREENSHOT_DIR override' {
        # Dot-source a fresh instance with the env var set.
        $env:CLAUDE_SCREENSHOT_DIR = 'C:\custom\path'
        try {
            $probe = & pwsh.exe -NoProfile -Command ". '$script:CapturePath' -DotSourceOnly; `$SCREENSHOT_DIR"
            $probe.Trim() | Should -Be 'C:\custom\path'
        } finally {
            Remove-Item Env:\CLAUDE_SCREENSHOT_DIR -ErrorAction SilentlyContinue
        }
    }
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement** — replace `:122-124`:

```powershell
$SCREENSHOT_DIR = if ($env:CLAUDE_SCREENSHOT_DIR) {
    $env:CLAUDE_SCREENSHOT_DIR
} else {
    "$env:LOCALAPPDATA\claude-screenshots"
}
$TEMP_DIR = "$env:TEMP\claude-screenshots"
foreach ($d in @($SCREENSHOT_DIR, $TEMP_DIR)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```
git commit -m "fix(screenshot): default output dir to LOCALAPPDATA; support CLAUDE_SCREENSHOT_DIR override"
```

---

### Task C3: Sanitize `-Proc` and error `$Detail` through `ConvertTo-SafeTitle`

**Files:** `capture.ps1:596, 608, 627, 629, 832`

- [ ] **Step 1: Write failing test**

```powershell
It 'sanitizes pipe-character in error detail' {
    # Simulate a no_match with a malicious proc value (contains '|')
    # The Detail string must URL-encode the '|'.
    $r = Resolve-Window -Proc 'foo|bar'
    $r.NoMatch | Should -BeTrue
    $r.Detail | Should -Not -Match '\|bar'
    $r.Detail | Should -Match '%7C'
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

Wherever the code builds a `Detail = "...=$variable"` or `Detail = "...=$procFilter"`, pass the variable through `ConvertTo-SafeTitle`. Specifically:

`:596`: `Detail = "no_match|pid=$TargetPid"` → `Detail = "no_match|pid=$TargetPid"` (safe, int).
`:608`: `Detail = "no_match|proc=$procFilter"` → `Detail = "no_match|proc=$(ConvertTo-SafeTitle $procFilter)"`.
`:627`: `$detail = "no_match|title=$(ConvertTo-SafeTitle $WindowTitle)"` — already safe.
`:628`: `if ($procFilter) { $detail += "|proc=$procFilter" }` → `if ($procFilter) { $detail += "|proc=$(ConvertTo-SafeTitle $procFilter)" }`.
`:832`: `detail = $resolved.Detail` — already safe since all producers sanitize.

Also at `:862`: `detail = "$_"` (exception message) — wrap: `detail = (ConvertTo-SafeTitle "$_")`.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```
git commit -m "security(screenshot): sanitize -Proc and exception detail through ConvertTo-SafeTitle"
```

---

## Section D — Robustness (spec §3.3)

### Task D1: Wrap `DwmGetWindowAttribute` in try/catch for missing dwmapi.dll

**Files:** `capture.ps1:340-347`

- [ ] **Step 1: Write failing source-grep test**

This defensive path cannot be exercised without a DLL-less SKU. Lock in the intent at the source level.

```powershell
Describe 'DwmGetWindowAttribute fallback' {
    It 'wraps DwmGetWindowAttribute in DllNotFoundException catch' {
        $src = Get-Content $script:CapturePath -Raw
        $src | Should -Match 'DwmGetWindowAttribute[\s\S]{0,300}System\.DllNotFoundException'
    }
}
```

Run — expect FAIL.

- [ ] **Step 2: Implement**

Replace:

```powershell
    $ef = New-Object Win32+RECT
    $size = [System.Runtime.InteropServices.Marshal]::SizeOf([type]([Win32+RECT]))
    $hr = try {
        [Win32]::DwmGetWindowAttribute($Hwnd, 9, [ref]$ef, $size)
    } catch [System.DllNotFoundException] { -1 }
    if ($hr -eq 0) {
        $extendedFrame = @{ Left = $ef.Left; Top = $ef.Top; Right = $ef.Right; Bottom = $ef.Bottom }
    } else {
        $extendedFrame = $windowRect.Clone()
    }
```

- [ ] **Step 3: Run — expect PASS**

- [ ] **Step 4: Commit**

```
git commit -m "fix(screenshot): tolerate missing dwmapi.dll (Server Core / Nano)"
```

---

### Task D2: Validate bitmap dimensions before `New-Object Bitmap(...)`

**Files:** `capture.ps1:414, 437, 684, 757, 911, 979` + helpers that construct bitmaps.

- [ ] **Step 1: Write failing test**

```powershell
Describe 'Degenerate bitmap guard' {
    It 'Invoke-PrintWindow throws a structured error on zero-size bounds' {
        $bounds = @{
            ExtendedFrame = @{ Left=100; Top=100; Right=100; Bottom=100 }
        }
        { Invoke-PrintWindow -Hwnd ([IntPtr]::Zero) -Bounds $bounds } |
            Should -Throw -ExpectedMessage '*degenerate*'
    }
}
```

- [ ] **Step 2: Run — expect FAIL** (current code throws `ArgumentException` with no structured message).

- [ ] **Step 3: Implement** — in each bitmap-allocation site, prepend:

```powershell
    if ($w -le 0 -or $h -le 0) {
        throw "degenerate_region|w=$w|h=$h"
    }
```

In `crop` and `window-crop` modes (`:740-741`, `:957-958`): emit structured error instead of throwing. `window-crop` already does this (`:959`); add equivalent to `crop` mode:

```powershell
    if ($px_w -le 0 -or $px_h -le 0) {
        $full.Dispose()
        Write-Result -Kind 'error' -Payload ([ordered]@{
            reason = 'degenerate_crop'
            region_pct = "$Left,$Top,$Right,$Bottom"
        }) -Format $Format
        exit 4
    }
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```
git commit -m "fix(screenshot): guard every bitmap allocation against degenerate dimensions"
```

---

### Task D3: Clamp crop-mode percentages to image bounds

**Files:** `capture.ps1:739-744`

- [ ] **Step 1: Write failing source-grep test**

```powershell
Describe 'Crop mode clamping' {
    It 'clamps px_left/top to >= 0 and px_right/bottom to image bounds' {
        $src = Get-Content $script:CapturePath -Raw
        # crop mode block must reference Math]::Max(0, px_left) and Math]::Min(full.Width
        $src | Should -Match '\[Math\]::Max\(\s*0\s*,\s*\$px_left'
        $src | Should -Match '\[Math\]::Min\(\s*\$full\.Width'
    }
}
```

Run — expect FAIL.

- [ ] **Step 2: Implement** — after computing `$px_w`/`$px_h`:

```powershell
    $px_left   = [Math]::Max(0, $px_left)
    $px_top    = [Math]::Max(0, $px_top)
    $px_right  = [Math]::Min($full.Width,  $px_right)
    $px_bottom = [Math]::Min($full.Height, $px_bottom)
    $px_w = $px_right - $px_left
    $px_h = $px_bottom - $px_top
```

(Insert **before** the degenerate check from D2.)

- [ ] **Step 3: Run — expect PASS**

- [ ] **Step 4: Commit**

```
git commit -m "fix(screenshot): clamp crop percentages to image bounds (parity with window mode)"
```

---

### Task D4: Wrap `Image.FromFile` in try/finally

**Files:** `capture.ps1:732-745, 949-967`

- [ ] **Step 1: Write failing source-grep test**

```powershell
Describe 'Image.FromFile disposal' {
    It 'wraps FromFile result in try { } finally { Dispose }' {
        $src = Get-Content $script:CapturePath -Raw
        # Occurrences must exceed the current single-dispose count — specifically, a try/finally
        # block must contain FromFile followed later by .Dispose in a finally clause.
        ([regex]::Matches($src, '(?s)FromFile[\s\S]{0,800}finally\s*\{[^}]*Dispose')).Count |
            Should -BeGreaterOrEqual 2
    }
}
```

Run — expect FAIL.

- [ ] **Step 2: Implement** — in `crop` mode:

```powershell
    $full = [System.Drawing.Image]::FromFile($tempPath)
    try {
        # ... existing crop logic ...
    } finally {
        $full.Dispose()
    }
```

Same shape for `window-crop`. Remove the inline `$full.Dispose()` calls from the happy path.

- [ ] **Step 3: Run — expect PASS**

- [ ] **Step 4: Commit**

```
git commit -m "fix(screenshot): dispose FromFile handle in finally to release file lock on error"
```

---

### Task D5: `[GC]::KeepAlive` for `EnumWindows` callbacks

**Files:** `capture.ps1:580, 794`

- [ ] **Step 1: Write failing source-grep test**

```powershell
Describe 'EnumWindows delegate lifetime' {
    It 'calls GC KeepAlive on every EnumWindows callback' {
        $src = Get-Content $script:CapturePath -Raw
        $enumCount = ([regex]::Matches($src, '\[Win32\]::EnumWindows\(')).Count
        $keepAliveCount = ([regex]::Matches($src, '\[GC\]::KeepAlive\(')).Count
        $keepAliveCount | Should -BeGreaterOrEqual $enumCount
    }
}
```

Run — expect FAIL.

- [ ] **Step 2: Implement** — append after the two `EnumWindows` invocations:

```powershell
    [void][Win32]::EnumWindows($cb, [IntPtr]::Zero)
    [GC]::KeepAlive($cb)
```

Same for the `list-windows` callback at `:794`.

- [ ] **Step 3: Run — expect PASS**

- [ ] **Step 4: Commit**

```
git commit -m "fix(screenshot): KeepAlive EnumWindows delegate to prevent premature GC"
```

---

### Task D6: Temp cleanup by `CreationTime`

**Files:** `capture.ps1:663-665`

- [ ] **Step 1: Write failing source-grep test**

```powershell
Describe 'Temp cleanup' {
    It 'ages files by CreationTime, not LastWriteTime' {
        $src = Get-Content $script:CapturePath -Raw
        $src | Should -Match '\$_\.CreationTime\s*-lt'
        $src | Should -Not -Match 'capture_\*\.png.*LastWriteTime\s*-lt'
    }
}
```

Run — expect FAIL.

- [ ] **Step 2: Implement**:

```powershell
Get-ChildItem $TEMP_DIR -Filter "capture_*.png" -ErrorAction SilentlyContinue |
    Where-Object { $_.CreationTime -lt (Get-Date).AddHours(-1) } |
    Remove-Item -Force -ErrorAction SilentlyContinue
```

- [ ] **Step 3: Run — expect PASS**

- [ ] **Step 4: Commit**

```
git commit -m "fix(screenshot): age-purge by CreationTime (LastWriteTime can be perturbed)"
```

---

## Section E — Win32 additions and constant hoisting (spec §3.5)

### Task E1: Add `SetWindowPos` P/Invoke; hoist Win32 + timing constants

**Files:** `capture.ps1:65-117, ~120`

- [ ] **Step 1: Write failing test**

```powershell
Describe 'Win32 surface' {
    It 'imports SetWindowPos' {
        { [Win32]::SetWindowPos([IntPtr]::Zero, [IntPtr]::Zero, 0, 0, 0, 0, 0) } |
            Should -Not -Throw -ExceptionType ([System.Management.Automation.RuntimeException])
    }
    It 'defines HWND_TOP, SWP_NOMOVE, SWP_NOSIZE, SWP_NOACTIVATE constants' {
        $script:HWND_TOP | Should -Be ([IntPtr]::new(0))
        $script:SWP_NOMOVE | Should -Be 0x0002
        $script:SWP_NOSIZE | Should -Be 0x0001
        $script:SWP_NOACTIVATE | Should -Be 0x0010
    }
    It 'defines OVERLAY_HOLD_MS = 200' {
        $script:OVERLAY_HOLD_MS | Should -Be 200
    }
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

Add inside `Add-Type` block (alongside other `[DllImport("user32.dll")]` entries):

```csharp
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
        int X, int Y, int cx, int cy, uint uFlags);
```

After line 117 (`SetProcessDPIAware` call) — **crucially, above the `if ($DotSourceOnly) { return }` gate on line ~660** so the Pester tests that dot-source can see the constants — add a constants block:

```powershell
# Win32 constants (hoisted from magic numbers scattered through the script)
$HWND_TOP         = [IntPtr]::new(0)
$SWP_NOSIZE       = 0x0001
$SWP_NOMOVE       = 0x0002
$SWP_NOACTIVATE   = 0x0010
$SW_SHOWNOACTIVATE = 4
$SW_MINIMIZE      = 6
$GW_HWNDPREV      = 3
$DWMWA_EXTENDED_FRAME_BOUNDS = 9
$PW_RENDERFULLCONTENT = 2

# Timing constants (milliseconds)
$UNMINIMIZE_SETTLE_MS = 150
$RAISE_SETTLE_MS      = 100
$OVERLAY_HOLD_MS      = 200

# Bitmap sizing
$MAX_DIM_FULL     = 1568
$MAX_DIM_OVERVIEW = 1200
```

Replace the magic-number usages downstream:
- `:420`: `[uint32]2` → `[uint32]$PW_RENDERFULLCONTENT`
- `:491`: `[Win32]::ShowWindow($Hwnd, 4)` → `...$SW_SHOWNOACTIVATE`
- `:494`: `Start-Sleep -Milliseconds 150` → `Start-Sleep -Milliseconds $UNMINIMIZE_SETTLE_MS`
- `:499`: `[Win32]::ShowWindow($Hwnd, 6)` → `...$SW_MINIMIZE`
- `:342`: the inline `9` → `$DWMWA_EXTENDED_FRAME_BOUNDS`
- `:383`: `[Win32]::GetWindow($prev, 3)` → `...$GW_HWNDPREV`
- `1200.0` occurrences → `$MAX_DIM_OVERVIEW` (or `[double]$MAX_DIM_OVERVIEW`)
- `1568.0` occurrences → `[double]$MAX_DIM_FULL`

**Before committing**, use Grep to verify no magic numbers remain:

```
Grep pattern: '\b(1200\.0|1568\.0|\bShowWindow[^,]+,\s*(4|6)\)|GetWindow[^,]+,\s*3\))' on config/skills/screenshot/capture.ps1
```

Any match is a remaining magic number — replace it. Expected final grep count: 0.

Also extend `$PROBLEMATIC_PROCS` per spec §1:
```powershell
$PROBLEMATIC_PROCS = @(
    'chrome','msedge','brave','opera','steam','vlc','mpv','obs64','wezterm-gui',
    'teams','ms-teams','outlook','slack','zoom','wfica32','receiver','mstsc',
    'acrord32','acrobat','webexmta','code'
)
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```
git commit -m "refactor(screenshot): add SetWindowPos P/Invoke; hoist Win32 + timing constants"
```

---

## Section F — Raise-without-focus capture (spec §1) — the correctness fix

### Task F1: Rewrite the `restore` branch of `Capture-Window`

**Files:** `capture.ps1:488-501`

This is the highest-impact change. Test first in isolation, then integrate.

- [ ] **Step 1: Write failing test**

Functional verification requires a live window and is manual (see spec §5 manual checklist). For unit coverage, add a shape test that confirms the code path calls `SetWindowPos` and restores Z-order via a `finally` clause:

```powershell
Describe 'Capture-Window restore strategy' {
    It 'uses SetWindowPos with $HWND_TOP and $SWP_NOACTIVATE' {
        $src = Get-Content $script:CapturePath -Raw
        $src | Should -Match 'SetWindowPos\s*\(\s*\$Hwnd\s*,\s*\$HWND_TOP[\s\S]*?\$SWP_NOACTIVATE'
    }
    It 'captures zAnchor via GetWindow $GW_HWNDPREV before raising' {
        $src = Get-Content $script:CapturePath -Raw
        $src | Should -Match '\$zAnchor\s*=\s*\[Win32\]::GetWindow\(\s*\$Hwnd\s*,\s*\$GW_HWNDPREV'
    }
    It 'wraps restore body in try/finally' {
        $src = Get-Content $script:CapturePath -Raw
        $src | Should -Match '(?s)try\s*\{[\s\S]*?SetWindowPos[\s\S]*?\}\s*finally\s*\{[\s\S]*?(SW_MINIMIZE|zAnchor)'
    }
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement** — replace `capture.ps1:488-501` with:

```powershell
    # restore strategy — raise-without-focus, capture, restore prior Z-order.
    # This is the correctness fix for the v1 bug where SW_SHOWNOACTIVATE
    # un-minimized the target but left the foreground window covering it,
    # so CopyFromScreen returned the foreground's pixels.
    $wasMinimized = $bounds.IsMinimized
    $zAnchor = [Win32]::GetWindow($Hwnd, $GW_HWNDPREV)  # may be IntPtr::Zero if already topmost

    try {
        if ($wasMinimized) {
            [void][Win32]::ShowWindow($Hwnd, $SW_SHOWNOACTIVATE)
            Start-Sleep -Milliseconds $UNMINIMIZE_SETTLE_MS
        }
        # Raise to top of Z-order WITHOUT stealing keyboard focus.
        [void][Win32]::SetWindowPos(
            $Hwnd, $HWND_TOP, 0, 0, 0, 0,
            ([uint32]($SWP_NOMOVE -bor $SWP_NOSIZE -bor $SWP_NOACTIVATE))
        )
        Start-Sleep -Milliseconds $RAISE_SETTLE_MS

        # [OVERLAY HOOK — Section G] Show-CaptureOverlay + shutter go here.
        # For this task: no overlay yet; skip to capture.

        $fresh = Get-WindowBounds -Hwnd $Hwnd
        $bmp = Invoke-ScreenCopy -Bounds $fresh
    }
    finally {
        if ($wasMinimized) {
            [void][Win32]::ShowWindow($Hwnd, $SW_MINIMIZE)
        } elseif ($zAnchor -ne [IntPtr]::Zero) {
            # Restore prior Z-order: insert $Hwnd after $zAnchor.
            [void][Win32]::SetWindowPos(
                $Hwnd, $zAnchor, 0, 0, 0, 0,
                ([uint32]($SWP_NOMOVE -bor $SWP_NOSIZE -bor $SWP_NOACTIVATE))
            )
        }
    }
    @{ Bitmap=$bmp; Strategy='restore'; Bounds=$fresh; BlankInfo=$null }
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```
git commit -m "fix(screenshot): raise-without-focus in restore strategy (occlusion correctness)"
```

---

### Task F2: Manual functional verification of F1

This is a manual check — record the result in the changelog in task L1.

- [ ] Arrange: open a full-screen terminal, open a second window (e.g. Notepad) behind it, minimize Notepad.
- [ ] Run: `<prefix> -Mode window -WindowTitle 'Notepad' -Strategy restore`
- [ ] Verify the output PNG shows Notepad, not the terminal.
- [ ] Verify Notepad returned to its minimized state.
- [ ] Verify keyboard focus remained on the terminal (type a few keys mid-capture and confirm they land in the terminal).
- [ ] If any check fails, STOP and debug before proceeding. Record outcome in plan (append to this task).

---

## Section G — Shutter + overlay (spec §2)

> **Ordering note:** Do Section H (renames) **before** this section if you want the G-series code blocks to use the final function name `Invoke-WindowCapture`. The code blocks as written use `Capture-Window`; the `replace_all` in H1 will then rename them in place. Either order works — pick one and be consistent.

### Task G1: Commit the shutter asset + README

**Files:** `config/skills/screenshot/assets/shutter.wav`, `assets/README.md`

- [ ] **Step 1: Source a CC0/public-domain camera-shutter sample** (freesound.org CC0 tier, or other clearly-PD source). Trim to < 500 ms. Re-encode to PCM 16-bit mono 22050 Hz. Verify the file is < 20 KB:
```
ffmpeg -i source.wav -t 0.5 -ac 1 -ar 22050 -acodec pcm_s16le \
    config/skills/screenshot/assets/shutter.wav
```

- [ ] **Step 2: Write `assets/README.md`**:

```markdown
# Screenshot skill assets

## shutter.wav

Camera-shutter click used to audibly confirm each screen capture.

- Format: PCM 16-bit, mono, 22050 Hz, ~300 ms.
- License: CC0 / Public Domain.
- Source: <exact URL of the freesound.org CC0 page>.
- Author: <as credited on source>.

Replacement policy: any CC0/PD shutter sample < 20 KB, < 500 ms, mono.
Longer clips will be truncated by playback timing (overlay hides after
200 ms per `$OVERLAY_HOLD_MS`).
```

- [ ] **Step 3: Commit**

```
git add config/skills/screenshot/assets/shutter.wav config/skills/screenshot/assets/README.md
git commit -m "feat(screenshot): add CC0 shutter.wav asset"
```

---

### Task G2: Implement `Show-CaptureOverlay` and `Hide-CaptureOverlay`

**Files:** `capture.ps1` — new helper functions after `Invoke-ScreenCopy`

- [ ] **Step 1: Write failing test**

```powershell
Describe 'Overlay helpers' {
    It 'defines Show-CaptureOverlay and Hide-CaptureOverlay' {
        Get-Command Show-CaptureOverlay -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command Hide-CaptureOverlay -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
    It 'Hide-CaptureOverlay tolerates being called without a prior Show' {
        { Hide-CaptureOverlay } | Should -Not -Throw
    }
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement** — add after `Invoke-ScreenCopy`:

```powershell
# WPF assembly load is deferred: importing PresentationFramework at script top
# adds ~80ms to every invocation even for pure-data modes (list, list-windows).
function Initialize-OverlayAssemblies {
    if ($script:_wpfLoaded) { return }
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $script:_wpfLoaded = $true
}

function Show-CaptureOverlay {
    param(
        # Target rect in virtual-screen pixels (whole screen for overview).
        [Parameter(Mandatory=$true)][int]$Left,
        [Parameter(Mandatory=$true)][int]$Top,
        [Parameter(Mandatory=$true)][int]$Right,
        [Parameter(Mandatory=$true)][int]$Bottom
    )
    Initialize-OverlayAssemblies

    $vsLeft   = [System.Windows.SystemParameters]::VirtualScreenLeft
    $vsTop    = [System.Windows.SystemParameters]::VirtualScreenTop
    $vsWidth  = [System.Windows.SystemParameters]::VirtualScreenWidth
    $vsHeight = [System.Windows.SystemParameters]::VirtualScreenHeight

    $win = New-Object System.Windows.Window
    $win.WindowStyle = 'None'
    $win.AllowsTransparency = $true
    $win.Background = [System.Windows.Media.Brushes]::Transparent
    $win.Topmost = $true
    $win.ShowInTaskbar = $false
    $win.IsHitTestVisible = $false
    $win.Left = $vsLeft; $win.Top = $vsTop
    $win.Width = $vsWidth; $win.Height = $vsHeight
    $win.ResizeMode = 'NoResize'

    $canvas = New-Object System.Windows.Controls.Canvas
    $canvas.Width = $vsWidth; $canvas.Height = $vsHeight

    # Even-odd geometry: full virtual screen XOR target rect → dims everything except the cut-out.
    $vsRectGeom = New-Object System.Windows.Media.RectangleGeometry(
        (New-Object System.Windows.Rect 0, 0, $vsWidth, $vsHeight))
    $targetLocalLeft   = $Left   - $vsLeft
    $targetLocalTop    = $Top    - $vsTop
    $targetLocalWidth  = $Right  - $Left
    $targetLocalHeight = $Bottom - $Top
    $targetRectGeom = New-Object System.Windows.Media.RectangleGeometry(
        (New-Object System.Windows.Rect $targetLocalLeft, $targetLocalTop, $targetLocalWidth, $targetLocalHeight))

    $group = New-Object System.Windows.Media.GeometryGroup
    $group.FillRule = 'EvenOdd'
    $group.Children.Add($vsRectGeom)
    $group.Children.Add($targetRectGeom)

    $dim = New-Object System.Windows.Shapes.Path
    $dim.Data = $group
    $dim.Fill = New-Object System.Windows.Media.SolidColorBrush(
        [System.Windows.Media.Color]::FromArgb(128, 0, 0, 0))  # #80000000
    $canvas.Children.Add($dim) | Out-Null

    # Marching-ants border: outer black dashed, inner white dashed offset 4.
    foreach ($pair in @(@{Brush='Black';Offset=0}, @{Brush='White';Offset=4})) {
        $rect = New-Object System.Windows.Shapes.Rectangle
        $rect.Width = $targetLocalWidth; $rect.Height = $targetLocalHeight
        [System.Windows.Controls.Canvas]::SetLeft($rect, $targetLocalLeft)
        [System.Windows.Controls.Canvas]::SetTop($rect,  $targetLocalTop)
        $rect.Stroke = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.Color]::FromName($pair.Brush))
        $rect.StrokeThickness = 1
        $rect.StrokeDashArray = New-Object System.Windows.Media.DoubleCollection @(4.0, 4.0)
        $rect.StrokeDashOffset = $pair.Offset
        $rect.Fill = [System.Windows.Media.Brushes]::Transparent
        $canvas.Children.Add($rect) | Out-Null
    }

    # Cyan L-shaped corner ticks (12x12 px)
    $cyan = New-Object System.Windows.Media.SolidColorBrush(
        [System.Windows.Media.Color]::FromRgb(0x00, 0xD2, 0xFF))
    foreach ($corner in @(
        @{x=$targetLocalLeft;                      y=$targetLocalTop;                      dx= 12; dy= 12},
        @{x=$targetLocalLeft+$targetLocalWidth;    y=$targetLocalTop;                      dx=-12; dy= 12},
        @{x=$targetLocalLeft;                      y=$targetLocalTop+$targetLocalHeight;   dx= 12; dy=-12},
        @{x=$targetLocalLeft+$targetLocalWidth;    y=$targetLocalTop+$targetLocalHeight;   dx=-12; dy=-12}
    )) {
        $tick = New-Object System.Windows.Shapes.Polyline
        $tick.Stroke = $cyan
        $tick.StrokeThickness = 2
        $pts = New-Object System.Windows.Media.PointCollection
        $pts.Add((New-Object System.Windows.Point ($corner.x + $corner.dx), $corner.y))
        $pts.Add((New-Object System.Windows.Point $corner.x, $corner.y))
        $pts.Add((New-Object System.Windows.Point $corner.x, ($corner.y + $corner.dy)))
        $tick.Points = $pts
        $canvas.Children.Add($tick) | Out-Null
    }

    $win.Content = $canvas
    $win.Show()
    # Let WPF compose one frame so the overlay is actually on-screen before we sleep.
    $win.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render)

    $script:_overlayWindow = $win
}

function Hide-CaptureOverlay {
    if ($null -ne $script:_overlayWindow) {
        try { $script:_overlayWindow.Close() } catch { }
        $script:_overlayWindow = $null
    }
}

function Start-ShutterSound {
    $wav = Join-Path $PSScriptRoot 'assets\shutter.wav'
    if (-not (Test-Path $wav)) {
        Write-Result -Kind 'warn' -Payload ([ordered]@{ reason = 'shutter_asset_missing' }) -Format $Format
        return
    }
    try {
        $player = [System.Media.SoundPlayer]::new($wav)
        $player.Play()  # async, fire-and-forget
    } catch { }
}
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```
git commit -m "feat(screenshot): WPF capture overlay + shutter sound helpers"
```

---

### Task G3: Integrate overlay + shutter into `overview` mode

**Files:** `capture.ps1:677-713`

- [ ] **Step 1: Implement** — in the `overview` branch, surround `CopyFromScreen` with the signal sequence:

```powershell
if ($Mode -eq "overview") {
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $captureId = Get-Date -Format 'yyyyMMdd_HHmmss_fff'

    Show-CaptureOverlay -Left $bounds.Left -Top $bounds.Top `
                        -Right $bounds.Right -Bottom $bounds.Bottom
    Start-ShutterSound
    Start-Sleep -Milliseconds $OVERLAY_HOLD_MS
    Hide-CaptureOverlay

    $full = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    # ...rest unchanged...
}
```

- [ ] **Step 2: Manual verification**: run `<prefix> -Mode overview`, observe a dim flash + shutter click, verify the saved PNG does **not** contain the overlay.

- [ ] **Step 3: Commit**

```
git commit -m "feat(screenshot): overlay + shutter on overview captures"
```

---

### Task G4: Integrate overlay + shutter into `window` mode

**Files:** `capture.ps1` — inside the rewritten `restore` branch from F1 (the `[OVERLAY HOOK]` marker); also for `printwindow` path.

For `printwindow` the overlay must fire **before** `PrintWindow` reads pixels. For `restore`, fire after the raise, before `CopyFromScreen`.

- [ ] **Step 1: Implement**

In `Capture-Window`, at the top (shared signal for both paths):

```powershell
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

    # Compute the rect that will actually be shown to the user for the overlay cut-out.
    # (region-crop happens later; overlay shows the whole window.)
    $signalRect = $bounds.ExtendedFrame

    if ($useStrategy -in @('auto','printwindow')) {
        Show-CaptureOverlay -Left $signalRect.Left -Top $signalRect.Top `
                            -Right $signalRect.Right -Bottom $signalRect.Bottom
        Start-ShutterSound
        Start-Sleep -Milliseconds $OVERLAY_HOLD_MS
        Hide-CaptureOverlay

        $bmp = Invoke-PrintWindow -Hwnd $Hwnd -Bounds $bounds
        try { $blank = Test-CaptureBlank -Bitmap $bmp } catch { $bmp.Dispose(); throw }
        if (-not $blank.IsBlank) {
            return @{ Bitmap=$bmp; Strategy='printwindow'; Bounds=$bounds; BlankInfo=$blank }
        }
        if ($Strategy -eq 'printwindow') {
            $bmp.Dispose()
            throw "capture_failed|pw_blank=yes|center_black=$($blank.CenterBlack)/9|overall_black=$($blank.OverallBlack)/25"
        }
        $bmp.Dispose()
        # Fell through to restore path. DON'T replay overlay — user just saw one.
        $skipOverlay = $true
    }

    # restore strategy (may have been reached via auto fallback)
    $wasMinimized = $bounds.IsMinimized
    $zAnchor = [Win32]::GetWindow($Hwnd, $GW_HWNDPREV)

    try {
        if ($wasMinimized) {
            [void][Win32]::ShowWindow($Hwnd, $SW_SHOWNOACTIVATE)
            Start-Sleep -Milliseconds $UNMINIMIZE_SETTLE_MS
        }
        [void][Win32]::SetWindowPos($Hwnd, $HWND_TOP, 0, 0, 0, 0,
            ([uint32]($SWP_NOMOVE -bor $SWP_NOSIZE -bor $SWP_NOACTIVATE)))
        Start-Sleep -Milliseconds $RAISE_SETTLE_MS

        if (-not $skipOverlay) {
            $fresh = Get-WindowBounds -Hwnd $Hwnd
            Show-CaptureOverlay -Left $fresh.ExtendedFrame.Left -Top $fresh.ExtendedFrame.Top `
                                -Right $fresh.ExtendedFrame.Right -Bottom $fresh.ExtendedFrame.Bottom
            Start-ShutterSound
            Start-Sleep -Milliseconds $OVERLAY_HOLD_MS
            Hide-CaptureOverlay
        } else {
            $fresh = Get-WindowBounds -Hwnd $Hwnd
        }

        $bmp = Invoke-ScreenCopy -Bounds $fresh
    }
    finally {
        if ($wasMinimized) {
            [void][Win32]::ShowWindow($Hwnd, $SW_MINIMIZE)
        } elseif ($zAnchor -ne [IntPtr]::Zero) {
            [void][Win32]::SetWindowPos($Hwnd, $zAnchor, 0, 0, 0, 0,
                ([uint32]($SWP_NOMOVE -bor $SWP_NOSIZE -bor $SWP_NOACTIVATE)))
        }
    }
    @{ Bitmap=$bmp; Strategy='restore'; Bounds=$fresh; BlankInfo=$null }
}
```

- [ ] **Step 2: Manual verification**: see spec §5 — capture a visible window, a minimized window, and a Chrome window. Each shows the overlay, plays the shutter, and returns the correct pixels without stealing focus.

- [ ] **Step 3: Commit**

```
git commit -m "feat(screenshot): overlay + shutter on window captures (printwindow and restore paths)"
```

---

## Section H — Renames (spec §3.5)

### Task H1: `Apply-Region` → `Resolve-RegionRect`; `Capture-Window` → `Invoke-WindowCapture`

**Files:** `capture.ps1`, `tests/capture.Tests.ps1`

- [ ] **Step 1: Implement**

Find-and-replace across both files. `replace_all`:
- `Apply-Region` → `Resolve-RegionRect`
- `Capture-Window` → `Invoke-WindowCapture`

- [ ] **Step 2: Run Pester — expect PASS**

- [ ] **Step 3: Commit**

```
git commit -m "refactor(screenshot): rename to approved PowerShell verbs (Invoke-, Resolve-)"
```

---

## Section I — New test cases (spec §5)

### Task I1: Add remaining spec §5 test cases

**Files:** `tests/capture.Tests.ps1`

- [ ] **Step 1: Append new cases** (each as its own `It` under an appropriate `Describe`):

```powershell
Describe 'Resolve-RegionRect — edge cases' {
    It 'top-strip on zero-height bounds yields zero height' {
        $b = @{ ExtendedFrame=@{ Left=0; Top=0; Right=100; Bottom=0 }; ClientRect=@{ Left=0; Top=0; Right=100; Bottom=0 } }
        $r = Resolve-RegionRect -Bounds $b -Region 'top-strip'
        ($r.Bottom - $r.Top) | Should -Be 0
    }
    It 'inverted center bounds produce degenerate rect (caller responsibility to detect)' {
        $b = @{ ExtendedFrame=@{ Left=100; Top=100; Right=50; Bottom=50 }; ClientRect=@{ Left=100; Top=100; Right=50; Bottom=50 } }
        $r = Resolve-RegionRect -Bounds $b -Region 'center'
        ($r.Right - $r.Left) | Should -BeLessOrEqual 0
    }
}

Describe 'Get-CandidateRanking stability' {
    # Sort-Object is NOT stable on Windows PowerShell 5.1 (unstable quicksort).
    # Stable sort was added in PS 7. We therefore either (a) scope this test to PS 7,
    # or (b) add `-Stable` inside Get-CandidateRanking. Choice: (b) — add `-Stable` to
    # the existing Sort-Object call so behaviour matches across runtimes. This is a
    # sub-task: before this test passes, edit capture.ps1:513-518 to include `-Stable`.
    It 'returns stable order when all candidates are equal' -Skip:($PSVersionTable.PSVersion.Major -lt 7 -and -not (Select-String -Path $script:CapturePath -Pattern '-Stable' -SimpleMatch -Quiet)) {
        $c = 1..5 | ForEach-Object {
            [pscustomobject]@{ Hwnd=[IntPtr]::new($_); IsForeground=$false; IsMinimized=$false; ZOrder=0; Area=100 }
        }
        $sorted = Get-CandidateRanking -Candidates $c
        ($sorted[0].Hwnd.ToInt32()) | Should -Be 1
        ($sorted[-1].Hwnd.ToInt32()) | Should -Be 5
    }
}

Describe 'Test-CaptureBlank — per-rule triggers' {
    BeforeAll {
        function _makeBitmap([int]$w, [int]$h, [scriptblock]$fill) {
            $bmp = New-Object System.Drawing.Bitmap $w, $h
            for ($y = 0; $y -lt $h; $y++) {
                for ($x = 0; $x -lt $w; $x++) {
                    $bmp.SetPixel($x, $y, (& $fill $x $y))
                }
            }
            $bmp
        }
    }
    It 'flags all-black as blank (centerBlack rule)' {
        $bmp = _makeBitmap 300 300 { param($x,$y) [System.Drawing.Color]::Black }
        (Test-CaptureBlank -Bitmap $bmp).IsBlank | Should -BeTrue
        $bmp.Dispose()
    }
    It 'flags all-white as blank (uniform-median rule)' {
        $bmp = _makeBitmap 300 300 { param($x,$y) [System.Drawing.Color]::White }
        (Test-CaptureBlank -Bitmap $bmp).IsBlank | Should -BeTrue
        $bmp.Dispose()
    }
    It 'does NOT flag a red→blue gradient as blank (per-channel variance)' {
        $bmp = _makeBitmap 300 300 {
            param($x,$y)
            $r = [int](255 * ($x / 299))
            $b = 255 - $r
            [System.Drawing.Color]::FromArgb($r, 0, $b)
        }
        (Test-CaptureBlank -Bitmap $bmp).IsBlank | Should -BeFalse
        $bmp.Dispose()
    }
}

Describe 'Asset presence' {
    It 'shutter.wav exists and is < 20 KB' {
        $wav = Join-Path (Split-Path $script:CapturePath -Parent) 'assets\shutter.wav'
        Test-Path $wav | Should -BeTrue
        (Get-Item $wav).Length | Should -BeLessThan 20480
    }
}
```

- [ ] **Step 2: Run — expect PASS** (all assertions should hold against the implementations from prior tasks).

- [ ] **Step 3: Commit**

```
git commit -m "test(screenshot): add v2 edge-case coverage (ranking, blank rules, assets)"
```

---

## Section J — Documentation (spec §3.6)

### Task J1: Update SKILL.md

**Files:** `config/skills/screenshot/SKILL.md`

- [ ] **Step 1: Apply edits**
  - Document `-Hwnd` as the primary flag (alias of `-WindowHwnd`). Show `-Hwnd <integer>` in the syntax block at line ~85.
  - Remove all `-First` references and its row from the flag list at ~93-96.
  - Fix `auto_resolved` doc: change `auto_resolved=yes|<reason>` to `auto_resolved=<reason>` at line ~89.
  - Add a "Transparency" section after "Window targeting" explaining:
    > Every `overview` and `window` capture plays a short shutter sound and flashes a dimming overlay with a cut-out around the captured region. There is no `-Silent` switch — this is intentional. Modify the script if you need silent captures for testing; accept that the user will no longer be notified.
  - Add a "Minimized windows" subsection under Workflow: explain that minimized windows are un-minimized silently, raised above the foreground, captured, and re-minimized — all without stealing keyboard focus.
  - Add a native-Windows invocation example near the top:
    ```powershell
    # Native Windows / PowerShell:
    & "$HOME\.claude\skills\screenshot\capture.ps1" -Mode overview
    ```
  - Document `$env:CLAUDE_SCREENSHOT_DIR` override in a new subsection under Cleanup.
  - Remove the `last_active=<epoch>` field from the disambiguation row example.
  - Add a note that `-Target <string>` is **not yet available** and a reference to the follow-ups spec.

- [ ] **Step 2: Verify by reading the whole file top to bottom** — do the examples still work against the new implementation? Flag any drift.

- [ ] **Step 3: Commit**

```
git commit -m "docs(screenshot): SKILL.md updates for v2 surface (alias, overlay, env override)"
```

---

## Section K — Mirror project config into `~/.claude` (per CLAUDE.md workflow)

### Task K1: No-op until changelog ships

Per this repo's convention (`CLAUDE.md`), the project is the source of truth. The live `~/.claude/skills/screenshot/` symlink picks up the changes automatically on next invocation. No separate deploy step.

- [ ] Confirm `~/.claude/skills/screenshot` is a symlink to `/mnt/d/labs/claude-code-optimizations/config/skills/screenshot` (or record the deploy step in the changelog).

---

## Section L — Changelog + branch finish

### Task L1: Write the changelog entry

**Files:** `changelogs/CHANGELOG-2026-04-17-screenshot-v2.md`, `CHANGELOG-SUMMARY.md`

- [ ] **Step 1:** Create `changelogs/CHANGELOG-2026-04-17-screenshot-v2.md` per the format in repo `CLAUDE.md`:
  - **Tag:** `[optional]` (breaking API surface for any existing agents that hard-coded `-WindowHwnd` as `[IntPtr]`).
  - **Summary:** "Screenshot skill v2 — raise-without-focus correctness fix, shutter+overlay user confirmation, 24 hardening fixes."
  - **Goal / Change / Deployment / Verification** sections as usual.
  - **Verification checklist** includes the manual tests from spec §5 (items 1–7) as checkboxes.
  - **Manual verification log** (populate with results from Task F2 and G3/G4 verification passes).

- [ ] **Step 2:** Append a one-line entry to `CHANGELOG-SUMMARY.md`.

- [ ] **Step 3:** Add this changelog filename to the local `.changelog-status` (current machine has already reviewed it).

- [ ] **Step 4: Commit**

```
git commit -m "docs: changelog for screenshot v2"
```

---

### Task L2: Full test pass + manual checklist

- [ ] Run full Pester suite. Expect all pre-existing tests plus every Describe/It added across Sections A–I to pass. Record the final `Tests Passed:` count in the changelog's verification section.
- [ ] Walk through spec §5 manual checklist items 1–7 end-to-end. Record any deviations in the changelog's manual-verification section.

- [ ] If a manual check fails: STOP. Do not mark plan complete. Fix the root cause and re-test.

---

### Task L3: Finish the branch

- [ ] Use `superpowers:finishing-a-development-branch` to decide PR vs merge. The branch currently carries the spec, followups doc, and this plan's commits on top of `main`.

---

## Risk notes for the executor

- **WPF in PowerShell 5.1 vs 7:** tested on both; `Add-Type -AssemblyName PresentationFramework` works on each. If you hit `Unable to load assembly` on a locked-down machine, the skill still captures correctly — overlay is a best-effort signal. Wrap `Initialize-OverlayAssemblies` body in try/catch and emit `warn|overlay_unavailable` on failure.
- **Regex-timeout test (C1) as written passes against current code** — it locks in the contract. The *integration* change (compiling `-Filter` with the timeout) has no direct Pester test because it runs inside a closure; verify by running the skill against a window title with a catastrophic pattern and confirming < 300 ms.
- **Bitmap-generation tests (I1) use `SetPixel`** — slow (~ hundreds of ms per bitmap at 300×300). Keep bitmap sizes small; these are edge-case proofs, not perf tests.
- **Overlay + shutter test surface is minimal**, because WPF show/hide is hard to assert in-process without a display. Manual checks carry most of this section's risk.
- **Focus-stealing regressions** are the highest-risk failure mode of F1/G4. Always verify with "type characters into the terminal mid-capture and confirm they land there" whenever touching the `restore` branch.

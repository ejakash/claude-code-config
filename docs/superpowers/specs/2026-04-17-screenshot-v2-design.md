# Screenshot Skill v2 — Correctness, Confirmation, Hardening

**Date:** 2026-04-17
**Status:** Design approved, pending implementation plan
**Predecessor:** `docs/superpowers/specs/2026-04-16-smart-screenshots-design.md`

## Problem

The v1 skill (shipped 2026-04-16) had three classes of issue surfaced by a hands-on audit:

1. **Correctness** — The `restore` strategy un-minimized a target with `SW_SHOWNOACTIVATE` but never raised its Z-order. When the user's active window (e.g. a full-screen terminal) covered the target's rect, `CopyFromScreen` captured the terminal's pixels instead of the target. Confirmed in a test capture of a minimized Discord window, which returned the terminal's content at Discord's coordinates.
2. **Transparency** — The agent captured screens with no perceptible signal to the user. On a busy desktop the user could not easily tell what, if anything, had just been photographed.
3. **Correctness + security debt** — Documented `-Hwnd` parameter did not exist (real name `-WindowHwnd` with an `[IntPtr]` type that rejected integer strings); `-CaptureId` accepted arbitrary paths; `-Filter` regex had no timeout; output path assumed the default `Pictures\Screenshots` location which OneDrive/KFM redirects; restore was not wrapped in try/finally so an exception left the user's window permanently un-minimized; plus a set of medium/low findings across robustness, portability, and PowerShell idioms.

## Goal

Produce a v2 of the skill that:

- Captures the intended window's pixels in every case (minimized, occluded, GPU-accelerated) without stealing keyboard focus.
- Gives the user an unavoidable audible + visual confirmation of every screen capture.
- Closes every issue identified in the 2026-04-17 audit, except the 330-line main-switch refactor, which is deferred.

## Non-goals

- The 330-line main-switch refactor (per-mode `Invoke-XMode` extractions, shared `Save-Scaled` / `Convert-PercentRect` helpers). Deferred to a follow-up so this change stays reviewable.
- Invoking Windows Snipping Tool programmatically. No stable public API exists; `ms-screenclip:` is interactive-only. We replicate the visual, not the tool.
- Cross-process MCP wrapper. The `-Format json` seam added in v1 stays in place; actual MCP integration is out of scope here.
- A silence / `-Silent` opt-out. Intentionally omitted: the agent must not be able to capture the user's screen without the user noticing. This is a product decision, not a technical one.

## Design

### 1. Capture correctness — `restore` becomes raise-without-focus for all non-foreground targets

The v1 `restore` strategy only un-minimized. v2 always raises the target to the top of the Z-order (without activating it) before reading pixels, then restores the prior Z position afterward.

**Sequence (applies to `window` mode with strategy `restore`):**

```
0. bounds = Get-WindowBounds -Hwnd $H           # includes IsMinimized
1. zAnchor = GetWindow($H, GW_HWNDPREV)         # window immediately above $H in Z order
2. if bounds.IsMinimized:
       ShowWindow($H, SW_SHOWNOACTIVATE)         # 4
       Sleep 150                                 # let DWM finish un-minimize animation
3. SetWindowPos($H, HWND_TOP, 0,0,0,0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)   # raise; do not steal focus
4. Sleep 100                                     # composition settle
5. Show-CaptureOverlay (see §2)
6. Sleep 200                                     # user perception window
7. Hide-CaptureOverlay
8. fresh = Get-WindowBounds -Hwnd $H             # re-read after un-minimize
9. bitmap = Invoke-ScreenCopy -Bounds $fresh     # overlay is gone; target is top; pixels are correct
10. (finally) if bounds.IsMinimized:
        ShowWindow($H, SW_MINIMIZE)              # 6
    else:
        SetWindowPos($H, zAnchor, 0,0,0,0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)
```

**Why not just always call `SetForegroundWindow`:** that approach (which the user considered) steals keyboard focus. Any typing in-flight at the moment of capture lands in the wrong window. Raise-without-focus gives us the same pixel correctness with zero focus disruption. `SetForegroundWindow` is explicitly rejected as a fallback — if raise-without-focus fails on some app we will investigate that app rather than reach for focus-stealing.

**`PrintWindow` path unchanged.** For visible, non-problematic windows, `PrintWindow` reads the target's own DC and is unaffected by occlusion. It remains the first strategy tried by `auto`. The restore path above applies when:
- The target is minimized, OR
- The target's process name is in `$PROBLEMATIC_PROCS`, OR
- `PrintWindow` returned a blank bitmap (detected by `Test-CaptureBlank`).

**`$PROBLEMATIC_PROCS` extension:** current list (`chrome`, `msedge`, `brave`, `opera`, `steam`, `vlc`, `mpv`, `obs64`, `wezterm-gui`) extended with `teams`, `ms-teams`, `outlook`, `slack`, `zoom`, `wfica32`, `receiver`, `mstsc`, `acrord32`, `acrobat`, `webexmta`, `code` (Electron). Adding `code` is necessary because VS Code is GPU-accelerated and was silently relying on the blank-fallback path.

### 2. Capture overlay + shutter sound

A WPF overlay, always on, synced with a shutter sound, dismissed before pixel readout.

**Overlay window:**

- `Window` with `AllowsTransparency=True`, `Background=Transparent`, `WindowStyle=None`, `ShowInTaskbar=False`, `Topmost=True`, `IsHitTestVisible=False` (click-through).
- Size: `SystemParameters.VirtualScreenWidth × VirtualScreenHeight`; positioned at `VirtualScreenLeft,VirtualScreenTop` so it covers all monitors including negative-coordinate secondaries.
- Content: a `Canvas` holding:
  - A `Path` whose `Data` is an even-odd `GeometryGroup` of (virtual-screen rect) ⊕ (target rect), filled `#80000000` — that is, the whole virtual screen at 50% black with the target rect cut out.
  - A marching-ants dotted border around the cut-out: two stacked `Rectangle`s, outer with `Stroke=Black StrokeDashArray=4,4`, inner with `Stroke=White StrokeDashArray=4,4 StrokeDashOffset=4`. Replicates the Windows Snipping Tool style.
  - Four small L-shaped corner ticks (12×12 px `Path` objects) in cyan (`#00D2FF`), anchored to the cut-out rect's corners.

**Sound:**

- Asset: `config/skills/screenshot/assets/shutter.wav` (~10 KB, PCM 16-bit, mono, short click — sourced from a public-domain shutter sample).
- Playback: `[System.Media.SoundPlayer]::new($path).Play()` — fire-and-forget async playback on a thread-pool thread.

**Timing:**

```
show overlay window    ───┐
                          │  200 ms hold (user perception)
play shutter sound     ───┘
hide overlay window    ───  ~0 ms (Hide is synchronous)
read pixels            ───  immediate (overlay is gone, does not appear in capture)
```

Hold duration is fixed at 200 ms. Longer than ~250 ms starts to feel like lag; shorter than ~150 ms risks being imperceptible. 200 ms is the sweet spot used by most screenshot tools.

**Mode-specific behavior:**

| Mode | Overlay | Sound |
|------|---------|-------|
| `overview` | Full virtual-screen dimmed, cut-out == whole screen (visually: whole screen flashes dimmer for 200 ms with dotted border around each monitor). | Yes. |
| `window` | Dim virtual screen with cut-out at target's `captured_rect`. | Yes. |
| `crop`, `window-crop`, `list`, `list-windows` | None (no new pixels are read). | None. |

**No opt-out.** There is deliberately no `-Silent` switch, no `-NoOverlay`, no environment variable to suppress either. If a user wants to capture without signal they must modify the script. This is the transparency contract with the user.

### 3. Bug and hardening fixes

The audit produced 25 findings; 24 are addressed in this spec (the main-switch refactor is deferred — see Non-goals). Fixes are grouped by file section.

#### 3.1 Parameter surface (capture.ps1:1–38)

- Add `[Alias('Hwnd')]` on `$WindowHwnd`. SKILL.md documented `-Hwnd`; script required `-WindowHwnd`. The alias resolves it without breaking any existing caller.
- Change `$WindowHwnd` type from `[IntPtr]` to `[long]`, converting to `IntPtr` internally. `[IntPtr]` cannot bind a bare integer string from the command line; `list-windows` emits `hwnd=526098` so round-tripping was impossible.
- Add `[ValidatePattern('^\d{8}_\d{6}_\d{3}$')]` on `$CaptureId`. Prevents path traversal like `-CaptureId '..\..\secret'` from escaping the temp dir.
- Add `[ValidateRange(0,100)]` on `$Left`, `$Top`, `$Right`, `$Bottom`.
- Remove `-First` switch. Unused in practice, documented as "non-deterministic escape hatch" — an anti-feature for agent workflows. Keep `-Best`.

#### 3.2 Security

- `-Filter` regex compiled with a 200 ms `MatchTimeout` via `[regex]::new($Filter, 'IgnoreCase', [TimeSpan]::FromMilliseconds(200))`. Prevents ReDoS via attacker-controlled window titles combined with agent-composed patterns.
- Default `$SCREENSHOT_DIR` moves from `$env:USERPROFILE\Pictures\Screenshots` (OneDrive-indexed, localized, not auto-created) to `$env:LOCALAPPDATA\claude-screenshots`. Overridable via `$env:CLAUDE_SCREENSHOT_DIR`. Directory auto-created with `New-Item -ItemType Directory -Force` if absent.
- All user-supplied strings (`-Proc`, `$Detail`) passed through `ConvertTo-SafeTitle` before interpolation into pipe-format error lines. Prevents pipe-injection attacks against output parsers.

#### 3.3 Robustness

- Wrap the entire `restore`-strategy body in try/finally (capture.ps1:488–501). The re-minimize and Z-order restore must run even on exception.
- Wrap `DwmGetWindowAttribute` call (capture.ps1:342) in try/catch for `DllNotFoundException` — handles Server Core / Nano SKUs without dwmapi.dll. Fall back to raw window rect.
- Validate bitmap dimensions (`$w > 0 -and $h > 0`) before every `New-Object System.Drawing.Bitmap(...)` call. Emit `error|reason=degenerate_region` rather than let `ArgumentException` propagate.
- Clamp `crop` percentages to image bounds (capture.ps1:744) the same way `window` mode already does at capture.ps1:889–891.
- Wrap `Image.FromFile($tempPath)` in try/finally with `Dispose()` in the finally, not in the happy path. Prevents exclusive file locks when an exception fires mid-crop.
- `[GC]::KeepAlive($cb)` after `EnumWindows` returns (capture.ps1:580). Prevents the delegate from being collected while native code is still invoking it.
- Temp-dir cleanup uses file `CreationTime` instead of `LastWriteTime` (capture.ps1:663–665). `LastWriteTime` can be influenced by anyone touching the file and is also reset by some antivirus scanners; `CreationTime` is set once at capture and is what we actually care about for age-based purge. Each PowerShell invocation is a fresh process — there is no cross-invocation session state, which is why the check is purely filesystem-based.
- `SCREENSHOT_DIR` creation at script init alongside `TEMP_DIR`.

#### 3.4 Output format

- `auto_resolved=yes|<reason>` collapses to `auto_resolved=<reason>` (single pipe-delimited field). Current form broke agents that split on `|` and then on `=`.
- Set `[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()` at script top. Titles containing non-ASCII (`®`, `©`, emoji) currently mangle to `?` in pipe output.
- Rename output filenames from `Screenshot <id>.png` to `Screenshot_<id>.png`. Embedded space breaks unquoted shell use downstream.
- Remove `last_active=0` field from ambiguous-candidate rows. It was never populated. Spec's promised error kinds `offscreen`, `window_gone`, `dwm_failed` are also struck from the v2 spec as unimplemented and not planned.

#### 3.5 PowerShell idioms

- Rename `Capture-Window` → `Invoke-WindowCapture`. Rename `Apply-Region` → `Resolve-RegionRect`. Both v1 names fail `PSUseApprovedVerbs` and block module packaging.
- Replace `Write-Host` in `Write-Result` (capture.ps1:137, 146) with `Write-Output`. Update tests to drop `6>&1` information-stream redirection.
- Hoist magic numbers to script-scope constants: `$MAX_DIM_FULL = 1568`, `$MAX_DIM_OVERVIEW = 1200`, `$OVERLAY_HOLD_MS = 200`, `$UNMINIMIZE_SETTLE_MS = 150`, `$RAISE_SETTLE_MS = 100`, plus all `SW_*`, `HWND_*`, `SWP_*`, `GW_*`, `DWMWA_*`, `PW_*` Win32 constants.

#### 3.6 Documentation

- SKILL.md: update `-Hwnd` with the new alias; document `-Target <string>` is **not** being introduced (deferred); document that no silence switch exists; add a minimized-window note; add a native-Windows invocation example alongside the WSL form; fix the `auto_resolved` field documentation; remove `-First` references; drop `last_active`; document `$env:CLAUDE_SCREENSHOT_DIR` override.

### 4. File layout

```
config/skills/screenshot/
├── SKILL.md                          (updated)
├── capture.ps1                       (updated, ~1100 lines after changes)
├── assets/
│   └── shutter.wav                   (new, binary, ~10 KB)
└── tests/
    ├── capture.Tests.ps1             (updated + new cases)
    └── pinvoke.smoke.ps1             (unchanged)
```

The overlay WPF code lives inline in `capture.ps1` as a helper function `Show-CaptureOverlay` / `Hide-CaptureOverlay`. Rationale: single-file deployment is simpler; WPF inline is ~80 lines; a separate `overlay.ps1` adds cross-file coupling for no real benefit.

`assets/shutter.wav` is a committed binary. Size budget < 20 KB. Source: any public-domain camera-shutter sample; the .wav will be checked into the repo under an explicit CC0/public-domain attribution note in a sibling `assets/README.md`.

### 5. Testing

Existing 29 Pester unit tests stay green after the rename (`Capture-Window` → `Invoke-WindowCapture`, `Apply-Region` → `Resolve-RegionRect`). New test cases added:

- `Resolve-RegionRect` with inverted bounds (Right < Left, Bottom < Top) → emits `error|degenerate_region`.
- `Get-CandidateRanking` with all-equal candidates → stable (deterministic) ordering.
- Percent→pixel math: `Left=50 Right=50` (zero-width), `Left=150` (out-of-range rejection at parameter validation).
- `Test-CaptureBlank` per-rule triggers: one test per rule (all-black, all-white, low-variance, center-black) asserting the specific counter.
- `Resolve-Window` extracted ranking logic: title-exact-match with proc-filter mismatch, PID + title simultaneously, whitespace-only title.
- `ConvertTo-SafeTitle` on `-Proc` and `$Detail` paths.
- Overlay lifecycle: `Show-CaptureOverlay` creates and shows a window; `Hide-CaptureOverlay` closes it; no WPF instance leaks after a capture (assert via `[System.Windows.Application]::Current` window count).
- Shutter sound: `.wav` asset exists, loads without exception (no audio assertion — not testable headlessly).

Functional tests that must pass post-implementation, validated manually with a checklist in the changelog:

1. Capture of a minimized window whose rect is entirely covered by the foreground terminal returns the minimized window's pixels (not the terminal's). Window returns to minimized state afterward; keyboard focus stays on the terminal throughout.
2. Capture of a fully-occluded-but-visible Chrome window returns Chrome's pixels.
3. Shutter sound plays on `overview` and `window` modes, not on `crop` / `window-crop` / `list` / `list-windows`.
4. Overlay visibly flashes on `overview` and `window`; dims only the virtual screen, cut-out shows the target; overlay is dismissed before pixel readout and never appears in the returned image.
5. `list-windows` → parse `hwnd=<N>` → `window -Hwnd <N>` round-trip works.
6. `-CaptureId '..\..\x'` rejected at parameter validation.
7. `-Filter '(a+)+b'` against a malicious long title completes within < 300 ms (timeout fires).
8. All 29 existing Pester tests + new cases pass.

### 6. Deployment & rollout

- Repo layout (from v1) unchanged: skill lives at `config/skills/screenshot/`, deployed as a symlink at `~/.claude/skills/screenshot/`. No migration step on machines that already picked up the v1 symlink — the first run of the updated script just works.
- New dependency: `shutter.wav` must be present in `assets/`. If missing, skill logs `warn|shutter_asset_missing` and proceeds with overlay-only signal (no sound). Treated as non-fatal so a corrupted checkout doesn't break capture entirely.
- New env var: `$env:CLAUDE_SCREENSHOT_DIR` (optional). Documented in SKILL.md.
- PowerShell version floor: still 5.1. WPF availability via `Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase` works on stock Windows PowerShell 5.1 and 7+. Not tested on PS Core on Linux (n/a — script is Windows-only).
- Pester version floor: still 5.0.0 (existing constraint).

### 7. Risk and open questions

- **Overlay on per-monitor DPI mismatches.** Virtual-screen coordinates are in physical pixels on Win10+ per-monitor-DPI-aware processes. The script already calls `SetProcessDPIAware()`; the WPF overlay will be positioned/sized in physical pixels to match. Mixed-DPI multi-monitor (e.g. 4K primary + 1080p secondary) is a known fragile case for WPF; we will test and document any limitations.
- **Sound playback latency.** `SoundPlayer.Play()` queues audio asynchronously; on a cold start the first sound may lag 50–100 ms. Acceptable given the 200 ms overlay hold.
- **Shutter asset sourcing.** Need a true public-domain or CC0 camera-shutter .wav. Plan: source from freesound.org CC0 tier, trim to < 500 ms, re-encode to PCM 16-bit mono 22050 Hz, verify size < 20 KB.
- **VS Code in `$PROBLEMATIC_PROCS`.** Adding `code` means every VS Code capture now runs through the restore-strategy raise-to-top path, which will visibly reorder windows. If that turns out to be intrusive in practice, we fall back to trying `PrintWindow` first (auto strategy) and let the blank-detect fallback handle it — this is the existing `auto` behavior, so no change needed; the `$PROBLEMATIC_PROCS` addition is an optimization, not a correctness requirement.
- **Main-switch refactor deferral.** The 330-line switch with ~4× duplication is a known debt. Deferring is a deliberate scope decision, not an oversight. A follow-up spec will handle it.

## Success criteria

1. Every bug listed in the 2026-04-17 audit is either fixed or explicitly deferred in this spec's Non-goals.
2. A capture of any window — minimized, occluded, GPU-accelerated — returns that window's pixels, confirmed by visual inspection of the returned PNG against the expected content.
3. Every screen capture produces a shutter sound and a visible overlay; there is no code path through the skill that emits a new PNG silently.
4. Keyboard focus does not shift during any capture.
5. All 29 existing Pester tests pass; new test cases (§5) pass.
6. SKILL.md examples work as written, top to bottom, on a fresh checkout.

## Follow-ups (not in this change)

- Main-switch refactor: extract `Invoke-OverviewMode` / `Invoke-CropMode` / `Invoke-WindowMode` / `Invoke-WindowCropMode`, share `Save-Scaled` and `Convert-PercentRect`. Target: cut capture.ps1 from ~1100 to ~800 lines.
- `-Target` polymorphic parameter (v1 audit recommendation #3) to collapse `-WindowTitle` / `-Pid` / `-Hwnd` / `-Proc` surface.
- CI workflow running Pester on windows-latest runners.
- Signed script + removal of `-ExecutionPolicy Bypass` from SKILL.md invocation.

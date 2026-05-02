# CHANGELOG-2026-04-16-smart-screenshots

**Date:** 2026-04-16
**Tag:** [core]
**Summary:** Window-aware screenshot capture — enumerate, target by title/PID/HWND, crop to content area. Cuts common "show me app X" flows from ~2,500 to ~1,000 tokens.

## Goal

The original screenshot skill forced every workflow through a ~1,080-token `overview` thumbnail before the agent could zoom in — then cropped by eyeballed screen-relative percentages. Small UI regions (dialogs, single panels) were hard to isolate cleanly.

This change lets the agent enumerate open windows and capture one directly, with pixel-perfect client-area cropping. Multi-monitor aware, handles minimized and GPU-accelerated windows gracefully, graceful disambiguation when multiple windows of the same app are open.

## Change

**Repo-layout change (one-time):** the skill is now version-controlled directly in this repo at `config/skills/screenshot/`, and `~/.claude/skills/screenshot/` is a symlink to the repo path. No more changelog-based mirror workflow for this skill.

**New files in the skill:**
- `config/skills/screenshot/tests/capture.Tests.ps1` — Pester v5 unit suite (29 tests covering all pure helpers)
- `config/skills/screenshot/tests/pinvoke.smoke.ps1` — one-off smoke for the Win32 P/Invoke surface

**`config/skills/screenshot/capture.ps1` — major extension:**
- Replaced minimal `DPI` Add-Type with full `Win32` class: 16 user32.dll methods + 1 dwmapi.dll method (`DwmGetWindowAttribute`)
- Added constants: `$PROBLEMATIC_PROCS`, `$SCREENSHOT_DIR`, `$TEMP_DIR`
- Added pure helpers (all unit-tested): `Write-Result` (with `-Format pipe|json`), `ConvertTo-SafeTitle`, `Get-ProcessName`, `Apply-Region`, `Test-CaptureBlank`, `Get-CandidateRanking`
- Added Win32-dependent helpers (smoke-tested): `Get-WindowBounds`, `Get-PidForHwnd`, `Invoke-PrintWindow`, `Invoke-ScreenCopy`, `Capture-Window`, `Resolve-Ambiguity`, `Resolve-Window`
- Added new modes: `list-windows`, `window`, `window-crop`
- Added `-Format json` to every mode (seam for future MCP wrapper)
- Added `-DotSourceOnly` switch for test dot-sourcing
- Refactored existing `overview`/`crop`/`list` modes to emit through `Write-Result` — byte-identical pipe output preserved

**`config/skills/screenshot/SKILL.md` — documented new modes, region keywords, strategies, disambiguation, JSON output, updated token-budget table.**

**`$PROBLEMATIC_PROCS` list** (hardcoded, skip `PrintWindow` and go straight to `restore` strategy):
```
chrome, msedge, brave, opera, steam, vlc, mpv, obs64, wezterm-gui
```
WezTerm included defensively — PrintWindow on a GPU-accelerated terminal can destabilize it in some cases.

## Deployment

**Pre-req on a new machine:** Pester v5 must be installed. `powershell.exe -Command "Install-Module Pester -Force -SkipPublisherCheck -Scope CurrentUser"`. Must explicitly `Import-Module Pester -MinimumVersion 5.0.0` to load v5 (legacy 3.4.0 ships with Windows).

**One-time migration** (only if `~/.claude/skills/screenshot/` is not already a symlink):

```bash
# SAFETY: verify it's a real directory, not already a symlink
if [ -L ~/.claude/skills/screenshot ]; then
    rm ~/.claude/skills/screenshot
elif [ -d ~/.claude/skills/screenshot ]; then
    mv ~/.claude/skills/screenshot ~/.claude/skills/screenshot.bak
fi
# Replace <REPO_PATH> with this machine's clone path: <!-- edit per machine: repo clone path -->
ln -s <REPO_PATH>/config/skills/screenshot ~/.claude/skills/screenshot
```

After migration the skill is live — no further copy step needed for future changes.

## Verification

Run in WSL (from any directory):

1. **Backwards compat** — existing modes emit byte-identical output:
   ```bash
   powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w ~/.claude/skills/screenshot/capture.ps1)" -Mode overview
   ```
   Expect: `overview|<path>|1200x675|capture_id=<ID>`

2. **Pester unit suite:**
   ```bash
   powershell.exe -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path '<REPO_PATH>\config\skills\screenshot\tests\capture.Tests.ps1'"
   ```
   Expect: 29 tests passing.

3. **`list-windows`:**
   ```bash
   powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w ~/.claude/skills/screenshot/capture.ps1)" -Mode list-windows
   ```
   Expect: `windows|<N>` header, then N rows with `hwnd/pid/proc/title/rect/client/monitor/state/dpi/focus/zorder` fields.

4. **`window` — foreground app:**
   ```bash
   powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w ~/.claude/skills/screenshot/capture.ps1)" -Mode window -WindowTitle '<partial title>' -Best
   ```
   Expect: `window|<path>|<WxH>|capture_id=<ID>|...` with `auto_resolved=yes|<reason>` when heuristics fire.

5. **`window -Region content`** — image excludes title bar; dimensions < full.

6. **Known-problematic app (Chrome)** — should auto-pick `strategy=restore` (not `printwindow`).

7. **Minimized window** — still captures successfully via restore strategy; window returns to minimized state afterward.

8. **`-Format json`** — every mode emits one-line JSON parseable by `jq .`.

9. **`window-crop`** from a `window` capture — percentages are window-relative.

10. **Error paths:** bogus title → `error|reason=no_match|...`; missing `-CaptureId` on window-crop → `error|reason=missing_capture_id`; ambiguous title → `error|reason=ambiguous` plus pre-ranked candidate rows.

## Design docs

Full design and implementation plan live in this repo:
- `docs/superpowers/specs/2026-04-16-smart-screenshots-design.md`
- `docs/superpowers/plans/2026-04-16-smart-screenshots.md`

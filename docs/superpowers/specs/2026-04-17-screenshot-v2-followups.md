# Screenshot Skill — v2 Follow-ups (Handover)

**Status:** Screenshot v2 is complete (see `2026-04-17-screenshot-v2-design.md` and `changelogs/CHANGELOG-2026-04-17-screenshot-v2.md`). This document captures the work that was deliberately deferred from v2 and is ready for a fresh session to pick up.

**Handover prompt (copy-paste to a new session):**

> I'd like you to work on the follow-ups to the Claude Code screenshot skill v2. Read `docs/superpowers/specs/2026-04-17-screenshot-v2-followups.md` for the full context, scope, and acceptance criteria for each item. The skill lives at `config/skills/screenshot/` and is symlinked to `~/.claude/skills/screenshot/` on this machine. The v2 work is in `main`; these four items are independent and can be picked up in any order, though I've suggested sequencing in the doc. Start by reading the follow-ups doc and then ask me which item you should tackle first, or propose a sequencing if you want to work through all four.

---

## Repo orientation (for the agent)

- **Repo:** `/mnt/d/labs/claude-code-optimizations` (a curated reference of Claude Code config, shared across machines).
- **Skill path:** `config/skills/screenshot/`. This is the source of truth; `~/.claude/skills/screenshot/` is a symlink to it.
- **Entry point:** `config/skills/screenshot/capture.ps1`. After v2 this file is ~1100 lines.
- **Agent-facing docs:** `config/skills/screenshot/SKILL.md`.
- **Tests:** `config/skills/screenshot/tests/capture.Tests.ps1` (Pester v5). Run from WSL:
  ```bash
  powershell.exe -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path '$(wslpath -w config/skills/screenshot/tests/capture.Tests.ps1)' -Output Detailed"
  ```
- **Relevant prior docs:**
  - `docs/superpowers/specs/2026-04-16-smart-screenshots-design.md` — the v1 design (`window`, `list-windows`, etc.)
  - `docs/superpowers/specs/2026-04-17-screenshot-v2-design.md` — the v2 design (correctness, shutter, overlay, 24 bug fixes)
  - `changelogs/CHANGELOG-2026-04-17-screenshot-v2.md` — the deployment record for what's now on `main`
- **Repo conventions:** read `CLAUDE.md` first. Every change bakes on the live machine for a day or two before being contributed to the repo via a changelog under `changelogs/`. Machine-specific values (`YOUR_WSL_USER`, `YOUR_WIN_USER`, repo clone path) are marked with `# <-- edit per machine: <what>` and must not be committed to `config/`.

## What v2 shipped

For grounding: v2 delivered raise-without-focus capture correctness, a WPF overlay + shutter-sound confirmation on every screen-capturing mode, and closure on 24 of 25 audit findings. The single deliberate carve-out was the main-switch refactor (Follow-up 1 below), kept out of v2 to keep the change reviewable. Three other items — a polymorphic `-Target` parameter, CI, and code-signing — are future improvements that weren't blocking.

---

## Follow-up 1 — Main-switch refactor

**Problem.** After v2, `capture.ps1:667–996` is a ~330-line switch statement with four branches (`overview`, `crop`, `window`, `window-crop`) that share substantial logic but implement it inline:

- The "scale to 1568 long-edge with `HighQualityBicubic` then save PNG then emit `Write-Result`" block appears in three branches with minor variations.
- The percentage→pixel math for cropping appears in both `crop` (line ~735) and `window-crop` (line ~952) as copy-paste with slightly different variable names.
- The `HighQualityBicubic` resize + save is duplicated ~4 times.

As a result: (a) the main dispatch is hard to read, (b) mode logic can't be unit-tested because it lives inside a giant switch, and (c) any behavior change has to be made in three places.

**Goal.** Extract per-mode functions and shared helpers so the dispatch switch shrinks to ~20 lines and each mode body becomes independently testable.

**Target structure.**

```
# Shared helpers (top of script, after Win32 block and constants):
function Save-ScaledBitmap {
    param([System.Drawing.Bitmap]$Source, [int]$MaxDim, [string]$Path)
    # Single implementation of the HighQualityBicubic resize + PNG save.
    # Returns the saved dimensions as a hashtable @{ Width=...; Height=... }.
}

function Convert-PercentRect {
    param([int]$Width, [int]$Height, [float]$Left, [float]$Top, [float]$Right, [float]$Bottom)
    # Returns @{ X=...; Y=...; W=...; H=... } in pixels, with clamping.
    # Emits error|reason=degenerate_region via throw if W <= 0 or H <= 0.
}

function Get-TopLevelWindows {
    param([string]$Filter, [int]$TargetPid, [switch]$IncludeMinimized)
    # Shared EnumWindows callback + filtering used by Resolve-Window and list-windows.
    # Returns an array of window hashtables.
}

# Mode functions (one per mode, each ~15-30 lines):
function Invoke-OverviewMode   { param($Format) ... }
function Invoke-CropMode       { param($CaptureId, $Left, $Top, $Right, $Bottom, $Format) ... }
function Invoke-WindowMode     { param(...) ... }
function Invoke-WindowCropMode { param($CaptureId, $Left, $Top, $Right, $Bottom, $Format) ... }
function Invoke-ListMode       { param($Format) ... }
function Invoke-ListWindowsMode { param($Filter, $Format) ... }

# Dispatch at bottom of script:
switch ($Mode) {
    'overview'      { Invoke-OverviewMode -Format $Format }
    'crop'          { Invoke-CropMode -CaptureId $CaptureId -Left $Left -Top $Top -Right $Right -Bottom $Bottom -Format $Format }
    'window'        { Invoke-WindowMode -WindowHwnd $WindowHwnd -TargetPid $TargetPid -WindowTitle $WindowTitle -Proc $Proc -Region $Region -Strategy $Strategy -Best:$Best -Format $Format }
    'window-crop'   { Invoke-WindowCropMode -CaptureId $CaptureId -Left $Left -Top $Top -Right $Right -Bottom $Bottom -Format $Format }
    'list'          { Invoke-ListMode -Format $Format }
    'list-windows'  { Invoke-ListWindowsMode -Filter $Filter -Format $Format }
}
```

**Acceptance criteria.**

1. `capture.ps1` line count drops to ~800 or below (from ~1100).
2. Every existing Pester test continues to pass with zero modifications to the `capture.Tests.ps1` file — the rename is pure refactoring.
3. New Pester tests added for `Save-ScaledBitmap` (aspect ratio, short-edge ≤ MaxDim, PNG header in output) and `Convert-PercentRect` (normal rect, inverted throws, clamping at 0/100).
4. Byte-identical pipe output for all existing modes. Compare stdout of each mode before and after the refactor on a fixed fixture.
5. JSON output structure unchanged — field order may differ (JSON objects are unordered) but key set must match.
6. No new Win32 calls; no behavior changes.

**Risks.**

- Byte-identical output check must include the trailing newline handling. `Write-Output` vs `Write-Host` differ subtly; v2 already standardized on `Write-Output`, but `Write-Result` is the only sanctioned emitter — the refactor must keep that invariant.
- `$script:` state (`$script:all`, `$script:windows`, `$script:_filter`, `$script:_targetPid`) used inside `EnumWindows` callbacks is fragile. The refactor should either eliminate it via `GetNewClosure()` or a `[List[object]]` passed by reference, or keep the same pattern but scope it tighter to each invocation.
- This file is big enough that naive rewriting will introduce subtle regressions. Strongly recommend: TDD with before/after stdout capture as the primary regression gate.

**Estimated effort:** 1 focused session (~2–3 hours of work).

---

## Follow-up 2 — `-Target` polymorphic parameter

**Problem.** `window` mode currently takes four parallel flags for targeting: `-WindowTitle`, `-Pid`, `-Hwnd` (alias for `-WindowHwnd`), `-Proc`. The agent reading `SKILL.md` has to pick one and track precedence (`Hwnd > Pid > Proc-only > Title+Proc`). Every agent invocation has slightly different shape depending on what's known.

**Goal.** Replace the four flags with a single polymorphic `-Target <string>` that uses a tiny prefix convention:

| Prefix | Meaning | Example |
|--------|---------|---------|
| `hwnd:<N>` | Window handle | `-Target hwnd:526098` |
| `pid:<N>`  | Process ID    | `-Target pid:5940` |
| `proc:<name>` | Process name (no `.exe`) | `-Target proc:discord` |
| *(bare string)* | Window-title substring (existing behavior) | `-Target "Chrome"` |

`-Proc <name>` stays as an **optional disambiguation filter** on top (e.g., `-Target 'WezTerm' -Proc wezterm-gui` to exclude Firefox tabs whose title contains "WezTerm"). The four individual flags are **removed**, not aliased — this is a breaking change for anyone calling the script directly, but the skill is invoked by an LLM agent via `SKILL.md`, so updating the docs is the migration.

**Acceptance criteria.**

1. `window` mode accepts `-Target <string>` with prefix parsing; `-Proc` stays as a disambiguator.
2. `-WindowTitle`, `-Pid`, `-WindowHwnd`, `-Hwnd` (alias) all removed.
3. `SKILL.md` updated: one signature line for `window` mode instead of four; one-line precedence explanation; worked example for each prefix.
4. `Resolve-Window` function takes a parsed target object (`@{ Kind='hwnd|pid|proc|title'; Value=...; ProcFilter=... }`) rather than the current four parameters.
5. Prefix parsing is unit-tested: `hwnd:0x1A2B` (hex), `hwnd:526098` (decimal), `pid:abc` → error, bare string containing `:` (e.g., window title `"D: drive"` — how do we distinguish from a prefix? Proposal: prefixes must match `^(hwnd|pid|proc):` and be interpreted literally, anything else is a title substring. Document this.)
6. `error|reason=ambiguous` output still emits candidate rows; hint string updated to describe picking `-Target hwnd:<H>` from the list.
7. All existing Pester tests updated to the new parameter shape; no new test failures.

**Risks / open questions.**

- **Title substrings containing `:`**: real-world examples include "C: Drive", "11:30 meeting notes". The rule "prefix must match `^(hwnd|pid|proc):`" handles this but needs to be documented prominently, and the SKILL.md example list must cover it.
- **Colons in process names on Windows**: not allowed in exe filenames, so `proc:` prefix is safe.
- This is the single biggest UX-facing change available. Worth doing, but worth considering whether the `-Proc` disambiguator-on-top feels natural with prefixed targets. Possible alternative syntax: `-Target "proc:wezterm-gui/WezTerm"` (slash-separated proc-then-title). Decide during implementation.

**Estimated effort:** ~1 hour. Mostly parser + docs + test updates.

---

## Follow-up 3 — CI workflow

**Problem.** The skill has 29+ Pester tests but no CI. Regressions ship to the user's live machine before being caught. On a work machine with different corporate constraints (AV, ExecutionPolicy, Pester version), this matters more.

**Goal.** Add a GitHub Actions workflow that runs Pester on `windows-latest` for every push and pull request touching the skill.

**Target workflow** (`.github/workflows/screenshot-skill.yml`):

```yaml
name: screenshot-skill

on:
  push:
    paths:
      - 'config/skills/screenshot/**'
      - '.github/workflows/screenshot-skill.yml'
  pull_request:
    paths:
      - 'config/skills/screenshot/**'
      - '.github/workflows/screenshot-skill.yml'

jobs:
  pester:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Pester 5
        shell: pwsh
        run: |
          Install-Module Pester -Force -SkipPublisherCheck -Scope CurrentUser -MinimumVersion 5.0.0
          Import-Module Pester -MinimumVersion 5.0.0
      - name: Run Pester
        shell: pwsh
        run: |
          $config = New-PesterConfiguration
          $config.Run.Path = 'config/skills/screenshot/tests/capture.Tests.ps1'
          $config.Output.Verbosity = 'Detailed'
          $config.TestResult.Enabled = $true
          $config.TestResult.OutputPath = 'test-results.xml'
          Invoke-Pester -Configuration $config
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results
          path: test-results.xml
```

**Acceptance criteria.**

1. Workflow runs on every push/PR touching the skill.
2. All 29+ tests pass on the hosted `windows-latest` runner — note that GitHub runners have no interactive desktop, so the "smoke" tests (`Get-WindowBounds smoke`, `Capture-Window smoke`) that depend on `GetForegroundWindow` returning a real hwnd may need to be tagged as `-Skip` or `-Tag Interactive` and excluded in CI.
3. Test results uploaded as artifact.
4. README or SKILL.md badge added (optional).

**Risks.**

- The two smoke tests (`Tests.ps1:167–191`, pre-v2 line numbers) use live windowing APIs. On a headless CI runner `GetForegroundWindow` may return `IntPtr.Zero`, and the tests will fail. The fix is to tag those as `-Skip:($hwnd -eq [IntPtr]::Zero)` or `-Tag Interactive` and exclude Interactive tag in the CI config.
- The overlay and shutter-sound tests in v2 similarly need to be tagged if they actually instantiate WPF / load audio — verify.
- Pester v5 install via `Install-Module` on a clean runner takes 30–60s; workflow duration will be ~2 min.

**Estimated effort:** ~30 min. Mostly YAML + tagging.

---

## Follow-up 4 — Signing + remove `ExecutionPolicy Bypass`

**Problem.** `SKILL.md` documents the invocation as `powershell.exe -ExecutionPolicy Bypass -File ...`. Colleagues on corporate machines with WDAC, AppLocker, or Constrained Language Mode will either silently fail or (worse) learn to bypass policy as habit. An unsigned PS script that spawns `csc.exe` (via `Add-Type`) calling `user32.dll` P/Invoke is a textbook EDR tripwire on hardened fleets.

**Goal.** Sign `capture.ps1` with an Authenticode certificate and remove `-ExecutionPolicy Bypass` from the SKILL.md invocation.

**Target state.**

1. `capture.ps1` has a valid `# SIG # Begin signature block ... End signature block` trailer.
2. SKILL.md invocation becomes `powershell.exe -File "$(wslpath -w ~/.claude/skills/screenshot/capture.ps1)"` (no `-ExecutionPolicy Bypass`).
3. Repo documents the signing process for colleagues who fork / modify:
   - How to generate a self-signed cert (`New-SelfSignedCertificate`) for local use, or
   - How to use an org-issued code-signing cert (if the user obtains one for their workplace)
4. A `scripts/sign-screenshot.ps1` helper re-signs the script after edits (most contributors won't have the private key, so they'll work unsigned locally and the owner re-signs before publishing).

**Complications to work through.**

- **Key management.** Signing requires a private key. Options:
  1. Self-signed cert, installed in the colleague's TrustedPublishers store. Good enough for personal use, not for corporate fleets.
  2. An org-issued code-signing cert from the user's workplace. Better for the "share with colleagues" case if the user's employer issues such certs.
  3. `sigstore` / `GitHub Artifact Attestations` — emerging, PowerShell doesn't natively validate these yet. Not viable today.
- **Signed script editing.** Every edit breaks the signature. Development loop becomes: edit → test unsigned → sign → commit. A pre-commit hook that re-signs on commit would work if the private key is accessible; otherwise maintainer-only.
- **`Add-Type` + csc.exe.** Even with the .ps1 signed, the inline C# compilation writes an unsigned assembly to `%TEMP%` on first run. A fully corporate-friendly version would need to pre-compile the Win32 interop to a signed DLL shipped in the repo. That is likely out of scope unless the user actually hits AV trouble.
- **`powershell.exe` vs `pwsh.exe`.** PS 5.1 and PS 7 have different default execution policies and different signing semantics. Pick one as the reference and document.

**Acceptance criteria.**

1. A signed `capture.ps1` runs successfully under the default `RemoteSigned` execution policy.
2. SKILL.md invocation no longer includes `-ExecutionPolicy Bypass`.
3. Signing process documented in a new file — `config/skills/screenshot/SIGNING.md` — covering key generation, how to re-sign after edits, and how colleagues should verify the signature on first use.
4. If self-signed: explicit note that colleagues must import the cert into `TrustedPublishers` on first install, with the exact command.

**Risks / caveats.**

- This is the most environment-dependent follow-up. If the user doesn't have access to a real code-signing cert, the self-signed path is the only option — and self-signed + `TrustedPublishers` import is arguably worse UX than the current `Bypass` (colleagues now have to run an extra step). Consider whether this follow-up should wait until the user has a real cert.
- Nothing else in the skill currently depends on signing being done. This can be deferred indefinitely at low cost.

**Estimated effort:** 1–2 hours of research + ~1 hour of implementation, heavily dependent on cert availability.

---

## Also-known lower-priority items (audit leftovers)

These were flagged in the 2026-04-17 audit but were judged too low-impact to block v2 or warrant their own follow-up. Mentioning for completeness so they don't get lost:

- **No `SetProcessDpiAwarenessContext(PER_MONITOR_V2)`**: v2 still uses `SetProcessDPIAware()` (system-DPI-aware). On mixed-DPI multi-monitor setups (e.g., 4K primary + 1080p secondary) per-monitor DPI awareness gives more accurate rects. Swap-in is a one-line Win32 addition if a user actually hits bad rects.
- **Timestamp collision within the same millisecond**: capture IDs use `yyyyMMdd_HHmmss_fff`. Two rapid captures in the same ms overwrite. Append a 4-char random suffix if this ever happens in practice.
- **`Get-CandidateRanking` ties for all-equal candidates**: not deterministically ordered. Add a final `hwnd` tiebreak to make ranking fully deterministic.
- **`PrintWindow` non-zero return treated as success even on garbage content**: v2 kept the blank-heuristic check; the BOOL return is still ignored. Check the return value too as defense-in-depth.
- **Documentation drift surface**: each of the four follow-ups above touches `SKILL.md`. When any of them lands, re-read the full `SKILL.md` as a final check for staleness.

---

## Suggested sequencing

If the agent works through all four:

1. **CI first.** It's the shortest and creates a safety net for the subsequent refactors. 30 minutes, one PR.
2. **Main-switch refactor.** Pure refactoring with CI now catching regressions. 2–3 hours, one PR.
3. **`-Target` polymorphic parameter.** Now that mode bodies are extracted functions, adding a new parameter shape is a localized change. 1 hour, one PR.
4. **Signing.** Last because it's environment-dependent and non-blocking. Defer until the user has a code-signing cert plan.

Each follow-up gets its own `changelogs/CHANGELOG-YYYY-MM-DD-<title>.md` per the repo convention in `CLAUDE.md`. Mark all four as `[optional]` (not `[core]`) — none of them change observable behavior of the skill from the user's point of view, so adoption on other machines is a preference call.

## What the agent should NOT do

- **Do not re-open the v2 design decisions.** No `-Silent` flag, no `SetForegroundWindow` fallback, no programmatic Windows Snipping Tool invocation. These were deliberately rejected in the v2 brainstorm.
- **Do not combine multiple follow-ups into one PR.** Each is independently landable; bundling defeats the reviewability goal that drove the v2 carve-outs in the first place.
- **Do not touch files outside `config/skills/screenshot/`, `.github/workflows/`, and the relevant changelog/spec directories** unless explicitly asked.
- **Do not delete the v2 spec or the v2 changelog.** They're the historical record.

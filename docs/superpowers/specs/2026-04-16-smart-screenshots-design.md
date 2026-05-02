# Smart Window-Targeted Screenshots — Design

**Date:** 2026-04-16
**Status:** Draft, pending review

## Context

The current screenshot skill (`~/.claude/skills/screenshot/capture.ps1`) captures the full primary screen at 4K, then crops by screen-relative percentage. This has two costs:

1. **Token waste.** Every workflow starts with a ~1,080-token overview before the agent can narrow in, even when the target app is known ahead of time.
2. **Imprecision.** Crop coordinates are eyeballed from a 1200-px-wide thumbnail of a 4K screen. Small UI regions (dialogs, toolbars, single panels) are hard to carve out cleanly; the agent often needs a second crop.

Common flow today: `overview` → estimate percent coordinates → `crop`. Cost ~2,500 tokens, two round-trips, fuzzy edges.

This change adds **window-aware capture** so the agent can enumerate open windows, target one by title/PID/HWND, and receive a pixel-perfect crop of just that window — or just its content area, sans title bar. Monitor detection, minimized-window handling, and GPU-app fallbacks are built in. The existing `overview`/`crop`/`list` modes are preserved unchanged.

Expected outcome: "show me app X" drops from ~2,500 to ~1,000 tokens with sharper images and no manual coordinate math.

## Goals

- Enumerate open top-level windows with bounds, process, monitor, state, DPI, focus, and Z-order
- Capture a specific window directly — skipping overview entirely when the target is known
- Precise content-area capture (excludes title bar and borders) using the Win32 client rect
- Auto-handle minimized and GPU-accelerated windows without visible disruption in the common case
- Multi-monitor aware — follow the targeted window to whichever monitor it lives on
- Disambiguate gracefully when multiple windows of the same app are open
- Preserve 100% backward compatibility with existing `overview`/`crop`/`list` modes
- Machine-friendly JSON output available via `-Format json` (seam for a future MCP server)

## Non-goals

- Building the MCP server now. The JSON-output flag is enough to let a future MCP wrapper proxy the script with zero re-work, but the server itself is deferred.
- Pane-level precision inside terminals/editors. Whole-window and client-area crops cover the use cases we care about today.
- Virtual desktop / all-monitors composite capture. Overview mode stays primary-screen only; window mode follows the window to its monitor.
- Cross-platform. Windows-only (the skill already is).

## Design

### Architecture

Single-script skill stays single-script. `capture.ps1` gains:

- An extended P/Invoke block for new Win32 / DWM calls
- A shared output helper that emits either the existing pipe format or one-line compact JSON
- Four new helper functions (window resolve, bounds, blank detection, capture)
- Three new modes (`list-windows`, `window`, `window-crop`)
- A small hardcoded "known-problematic" process list for apps that fail under `PrintWindow`

Existing modes route through the new output helper but emit byte-identical pipe output when `-Format json` is not set — backwards compatible.

### New P/Invoke surface

Added to the existing `Add-Type` block:

**user32.dll:** `EnumWindows`, `GetWindowText`, `GetWindowTextLength`, `GetWindowRect`, `GetClientRect`, `ClientToScreen`, `IsIconic`, `IsWindowVisible`, `ShowWindow`, `PrintWindow`, `GetWindowThreadProcessId`, `MonitorFromWindow`, `GetForegroundWindow`, `GetWindow`, `GetDpiForWindow`

**dwmapi.dll:** `DwmGetWindowAttribute` (attribute 9 = `DWMWA_EXTENDED_FRAME_BOUNDS`) — required to get visible bounds without the invisible resize-shadow ~8px gutter that `GetWindowRect` returns on Windows 10/11.

### Helpers

**`Resolve-Window`**
Inputs (mutually exclusive): `-WindowTitle`, `-Pid`, `-Hwnd`. Plus: `-Best`, `-First`.
Output: a single HWND, or `ambiguous` payload with pre-sorted candidates, or `no_match`.

Resolution tiers, tried in order before returning `ambiguous`:

1. Exact-title match across visible windows → use it
2. Substring match with exactly one foreground (focused) match → use it
3. Substring match with exactly one *visible* match (others minimized) → use it
4. `-Best` flag set → pick the top-ranked candidate silently

Ranking for tie-breaking: `foreground > z-order (topmost first) > visible > minimized > larger bounds`.

**Flag semantics:**

- `-Best` — if the resolver would otherwise return `ambiguous`, pick the top-ranked candidate using the ranking above. Output includes `auto_resolved=yes|best`.
- `-First` — pure escape hatch. Returns the first match in `EnumWindows` iteration order (no ranking, non-deterministic across runs). Intended only for cases where the agent genuinely does not care which instance. Output includes `auto_resolved=yes|first`.

**Process-name matching:** the known-problematic list and all `proc=` fields use the process basename **without** `.exe` extension, **case-insensitive** (`Chrome`, `chrome.exe`, `CHROME` all match list entry `chrome`).

**`Get-WindowBounds -Hwnd`**
Returns `{WindowRect, ExtendedFrame, ClientRect(screen-space), Monitor, Dpi, IsMinimized, IsForeground, ZOrder}`. Prefers DWM extended frame as primary bounds; falls back to `GetWindowRect` on DWM failure. `ClientRect` is converted to screen coordinates via `ClientToScreen`.

**`Test-CaptureBlank -Bitmap`**
Multi-region sampling detector. Samples a 5×5 grid across the image plus a 3×3 dense cluster in the middle 30% (34 samples total). Returns `{IsBlank, CenterBlack, OverallBlack, StdDev}`.

Blank triggers (any one fires):

| Check | Threshold |
|-------|-----------|
| Near-black in center cluster | ≥ 7 of 9 with `R+G+B < 30` |
| Near-black overall | ≥ 20 of 25 with `R+G+B < 30` |
| Uniform single color | ≥ 23 of 25 within ΔRGB ≤ 5 of median |
| Per-channel variance | **R, G, and B** stddev across 25 grid samples each < 3 (corrected from earlier draft that used brightness-sum stddev — that rule false-positives on chromatic gradients where R+G+B stays ≈ constant while channels vary) |

Uniform-color check is skipped for windows < 200×200 px (small widgets legitimately have low variance).

**`Capture-Window -Hwnd -Strategy`**
Strategies:

- `auto` (default): try `PrintWindow` with flag `PW_RENDERFULLCONTENT` (0x2). Test with `Test-CaptureBlank`. On failure, fall through to `restore`. If process is in the hardcoded problematic list, skip `PrintWindow` entirely.
- `printwindow`: force `PrintWindow`, fail hard if blank.
- `restore`: `ShowWindow(SW_SHOWNOACTIVATE)` → `CopyFromScreen` at window bounds → `ShowWindow(SW_MINIMIZE)` if originally minimized. Preserves Z-order and keyboard focus (no focus-steal).

Known-problematic list (hardcoded at top of script, easy to edit):

```
chrome, msedge, brave, opera, steam, vlc, mpv, obs64
```

**`Apply-Region -Bounds -Region`**
Maps a region keyword to a pixel rectangle:

- `full` (default) — extended frame
- `content` — client rect (excludes title bar, borders) via `GetClientRect` + `ClientToScreen`
- `titlebar` — extended frame top strip, height = `ClientRect.top - ExtendedFrame.top`
- `left-half`, `right-half`, `top-half`, `bottom-half` — derived from extended frame
- `center` — middle 50% box of the extended frame (25–75% on both axes)
- `top-strip` — fixed top 5% of the window

### New modes

**`list-windows [-Filter <regex>]`**
Enumerates via `EnumWindows`. Filters by `IsWindowVisible` OR `IsIconic` (skips purely invisible tool windows). Emits one row per window.

Pipe output (one line per window):
```
windows|<count>
hwnd=<H>|pid=<P>|proc=<exe>|title=<escaped>|rect=<L,T,R,B>|client=<L,T,R,B>|monitor=<idx>|state=<visible|minimized>|dpi=<N>|focus=<yes|no>|zorder=<N>
```

Titles are URL-encoded (`%HH`) for `|`, newline, and `%` in pipe format. JSON format handles natively.

Note: `last_active=<epoch>` is **disambiguation-only** — emitted in `ambiguous` candidate rows (see below) but not in `list-windows`, since it requires a per-window query and is only meaningful when ranking siblings against each other.

**`window`**
Params: `-WindowTitle | -Pid | -Hwnd` (required, mutually exclusive), `-Region <keyword>` (default `full`), `-Strategy <auto|printwindow|restore>` (default `auto`), `-Best`, `-First`.

Flow: `Resolve-Window` → `Get-WindowBounds` → `Capture-Window` → `Apply-Region` crop → scale to 1568-px long edge → save full-res temp `capture_<id>.png` AND output `Screenshot <id>_window.png`. The `capture_id` lets `window-crop` zoom further without recapturing.

Output:
```
window|<path>|<WxH>|capture_id=<ID>|hwnd=<H>|proc=<exe>|region=<keyword>|strategy=<used>|window_rect=<L,T,R,B>|captured_rect=<L,T,R,B>
```

Includes `auto_resolved=yes|<reason>` if a heuristic picked the target.

**`window-crop`**
Params: `-CaptureId <id>`, `-Left -Top -Right -Bottom` as percentages **of the window capture** (not the screen). Same math as existing `crop`, but operating on a window-scoped temp file.

Output:
```
window-crop|<path>|<WxH>|capture_id=<ID>|region_pct=<L,T,R,B>
```

### Disambiguation

When `Resolve-Window` cannot auto-resolve, it returns pre-sorted candidates inline so the agent can pick without a second call:

```
ambiguous|matches=3
hwnd=<H>|pid=<P>|proc=<exe>|title=<escaped>|rect=...|focus=<yes|no>|zorder=<N>|last_active=<epoch>
hwnd=<H>|pid=<P>|proc=<exe>|title=<escaped>|rect=...|focus=<yes|no>|zorder=<N>|last_active=<epoch>
hwnd=<H>|pid=<P>|proc=<exe>|title=<escaped>|rect=...|focus=<yes|no>|zorder=<N>|last_active=<epoch>
```

Agent re-invokes with the chosen `-Hwnd`. `-Best` skips the disambiguation error entirely and picks the top-ranked candidate silently.

### Error handling

All errors emit structured output through the shared helper — nothing throws uncaught:

- `error|no_match|<detail>`
- `error|ambiguous|matches=<N>` + candidate rows
- `error|offscreen|hwnd=<H>` — window exists but on disconnected/virtual-desktop monitor
- `error|window_gone|hwnd=<H>` — window closed mid-capture
- `error|dwm_failed|hwnd=<H>` — DWM attribute call failed, fell back to `GetWindowRect`
- `error|capture_failed|hwnd=<H>|pw_blank=yes|center_black=<N>/9|overall_black=<N>/25` — both strategies exhausted

### Output format

`-Format pipe` (default) — existing format, extended.
`-Format json` — one-line compact JSON with identical fields. Every mode (including existing `overview`/`crop`/`list`) routes through the shared emitter so JSON output is uniform. This is the seam for a future MCP server: it can spawn `capture.ps1 -Format json`, pipe stdout, and skip parsing entirely.

### SKILL.md updates

Add sections after existing `## Modes`:
- Window targeting — `list-windows`, `window`, `window-crop` with examples
- Region keywords table
- Disambiguation — `-Best`, `-First`, candidate-row flow
- JSON output — `-Format json` for machine parsing
- Workflow update: mention `window` as a lower-token alternative when target is known
- Token budget table updated with window-mode numbers

## Token budget

| Call | Before | After |
|------|--------|-------|
| "Show me WezTerm" | overview (~1,080) + crop (~1,500) = **~2,580** | `window -Region content` (~1,200) = **~1,200** |
| "What's in that modal?" | overview + crop + often 2nd crop = **~3,500** | `window -Region center` (~1,000) = **~1,000** |
| Disambiguation | not supported — agent guesses from thumbnail | `ambiguous` response (~150 tokens, no image) |

## Testing

Manual smoke tests, run in order:

1. **Backwards compat:** `overview` and `crop` produce byte-identical output to current script (pipe format)
2. **`list-windows`:** WezTerm + a browser + one other app appear with sensible bounds; minimize one → `state=minimized` shows up
3. **`window` full:** `window -WindowTitle "WezTerm"` → image shows full terminal; bounds match `list-windows`
4. **`window` content:** `window -WindowTitle "WezTerm" -Region content` → pixel height < full-mode height (title bar excluded)
5. **Known-problematic:** `window -WindowTitle "Chrome" -Best` → output has `strategy=restore`; image non-blank
6. **Minimized capture:** minimize WezTerm → `window -WindowTitle "WezTerm"` → succeeds; window returns to minimized; output has `strategy=restore` and `pw_blank=yes`
7. **Ambiguity:** 3 Chrome windows, none focused → `ambiguous` with 3 pre-ranked candidates. Focus one → re-run → auto-resolves with `auto_resolved=yes|foreground`
8. **JSON:** every mode with `-Format json` pipes cleanly through `jq .`
9. **`window-crop`:** take a `window` capture → `window-crop ... -Left 50 -Top 0 -Right 100 -Bottom 50` returns top-right quadrant of the window, not the screen
10. **Token sanity:** file size of `window -Region content` of a code editor smaller than `overview + crop` of the same visual area

## Files

- `/home/pudge/.claude/skills/screenshot/capture.ps1` — extend
- `/home/pudge/.claude/skills/screenshot/SKILL.md` — document new modes
- Eventually: changelog entry in this repo per `CLAUDE.md` machine-→-project workflow

## Future work (explicitly out of scope now)

- **MCP server** wrapping the script. JSON output is the seam; build when call patterns stabilize and caching window enumeration actually pays off.
- **Monitor detection helper** as a separate tool that returns just the monitor/bounds for a window without capturing — could be useful for layout automation.
- **Pane-level precision** for specific apps (WezTerm Lua API, VS Code workbench inspection) if the client-rect default turns out to be too coarse.

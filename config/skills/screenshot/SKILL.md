---
name: screenshot
description: Use when needing to proactively capture what's on screen — verifying UI changes, inspecting visual output, checking browser state, or when user says "take a screenshot"
---

# Screenshot

Proactively capture the screen on Windows via WSL. For **reading** existing user-taken screenshots, see the Screenshots section in CLAUDE.md.

## Script

`~/.claude/skills/screenshot/capture.ps1` — all commands use this prefix:

```
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w ~/.claude/skills/screenshot/capture.ps1)"
```

## Modes

### Overview — take a screenshot

```bash
<prefix> -Mode overview
```

Output: `overview|<path>|<WxH>|capture_id=<ID>`

Captures full screen at native 4K, saves a full-res temp copy, outputs a 1200x675 overview (~1,080 tokens). The `capture_id` uniquely identifies this capture for later cropping.

After reading the overview, offer: *"I can zoom into any area if you need more detail — just point out the region."*

### Crop — zoom into a specific capture

```bash
<prefix> -Mode crop -CaptureId <ID> -Left <L> -Top <T> -Right <R> -Bottom <B>
```

Output: `crop|<path>|<WxH>|capture_id=<ID>|region=<L>,<T>,<R>,<B>`

Coordinates are **percentages (0-100)** of the full image. Crops from the stored 4K capture and scales to 1568px long edge for maximum detail.

- `-CaptureId` is optional — omit it to crop from the most recent capture
- Always include `-CaptureId` when multiple captures exist to avoid ambiguity

Common regions:
| Area | Left | Top | Right | Bottom |
|------|------|-----|-------|--------|
| Full title bar strip | 0 | 0 | 100 | 3 |
| Top-left quadrant | 0 | 0 | 50 | 50 |
| Taskbar | 0 | 96 | 100 | 100 |
| Center | 25 | 25 | 75 | 75 |

### List — show available captures

```bash
<prefix> -Mode list
```

Output: `available_captures|<id1>,<id2>,...`

Use this when unsure which captures are available, especially with multiple Claude instances.

## Window targeting

When the target application is known, `window` mode skips the overview step and captures just that window — sharper image, fewer tokens, no coordinate math.

### list-windows — enumerate open windows

```bash
<prefix> -Mode list-windows [-Filter <regex>]
```

Output: header `windows|<N>` then one row per window:
```
window|hwnd=<H>|pid=<P>|proc=<exe>|title=<escaped>|rect=<L,T,R,B>|client=<L,T,R,B>|monitor=<idx>|state=<visible|minimized>|dpi=<N>|focus=<yes|no>|zorder=<N>
```

`-Filter` is a PowerShell regex applied to titles, case-insensitive.

### window — capture a specific window

```bash
<prefix> -Mode window -WindowTitle <substring> [-Proc <name>] [-Region <keyword>] [-Strategy <s>] [-Best] [-First]
<prefix> -Mode window -Pid <N> ...
<prefix> -Mode window -Hwnd <handle> ...
<prefix> -Mode window -Proc <name> ...
```

Output: `window|<path>|<WxH>|capture_id=<ID>|hwnd=<H>|proc=<exe>|region=<keyword>|strategy=<used>|window_rect=<L,T,R,B>|captured_rect=<L,T,R,B>[|auto_resolved=yes|<reason>]`

- **`-WindowTitle`** — case-insensitive substring match; tiered auto-resolve (exact-title → foreground → single-visible)
- **`-Pid`** — match by process ID (errors if process has multiple windows unless `-Best`)
- **`-Hwnd`** — match by window handle (stable across title changes)
- **`-Proc`** — filter candidates by process name (lowercased, no `.exe`). Can be used alone (any window of that process) or combined with `-WindowTitle` to disambiguate title collisions. Example: `-WindowTitle 'WezTerm' -Proc 'wezterm-gui'` excludes Firefox tabs whose title contains "WezTerm".
- **`-Best`** — when ambiguous, pick the top-ranked candidate silently (foreground > z-order > visible > minimized > larger)
- **`-First`** — when ambiguous, pick the first enumerated candidate (non-deterministic, last-resort escape hatch)

### Region keywords

| Keyword | Covers |
|---------|--------|
| `full` (default) | Entire window (extended frame) |
| `content` | Client area — excludes title bar, borders (via `GetClientRect`) |
| `titlebar` | Title bar strip |
| `left-half`, `right-half`, `top-half`, `bottom-half` | Halves of extended frame |
| `center` | Middle 50% box (25–75% on both axes) |
| `top-strip` | Fixed top 5% |

### Strategies

| Strategy | Behavior |
|----------|----------|
| `auto` (default) | Try `PrintWindow` first; fall back to `restore` on blank result. Known-problematic apps (Chrome, Edge, Brave, Opera, Steam, VLC, mpv, OBS) skip straight to `restore`. |
| `printwindow` | Force `PrintWindow`, fail hard if blank |
| `restore` | Briefly unminimize/raise the window via `ShowWindow(SW_SHOWNOACTIVATE)` without stealing focus, copy from screen, re-minimize if originally minimized |

### Disambiguation

When multiple windows match and none of the auto-resolve tiers fire, the output is:
```
error|reason=ambiguous|matches=<N>
window|hwnd=<H>|pid=<P>|proc=<exe>|title=<escaped>|rect=...|focus=<y/n>|zorder=<N>|state=<v/m>|last_active=<epoch>
... (N pre-ranked rows)
```

The agent picks one via `-Hwnd <H>` from the desired row, or re-runs with `-Best`.

### window-crop — zoom into a window capture

```bash
<prefix> -Mode window-crop -CaptureId <ID> -Left <L> -Top <T> -Right <R> -Bottom <B>
```

Output: `window-crop|<path>|<WxH>|capture_id=<ID>|region_pct=<L,T,R,B>`

Same percentage math as `crop`, but the percentages are **relative to the window capture**, not the screen. Requires an explicit `-CaptureId` from a prior `window` call.

## JSON output

Every mode accepts `-Format json` for structured output:

```bash
<prefix> -Mode list-windows -Format json
```

Each emitted line is a one-line JSON object with the same fields as the pipe format plus a `kind` field. Useful for programmatic consumption (agents parsing stdout, future MCP wrappers).

## Workflow

**Unknown target:**
1. Run `overview`, read the saved image
2. Estimate percentage coordinates, run `crop`

**Known target app:**
1. Run `window -WindowTitle <substring>` (add `-Region content` to skip title bar)
2. If ambiguous, pick from candidates via `-Hwnd`, or use `-Best`
3. Further zoom with `window-crop -CaptureId <ID>` if needed

Multiple captures can coexist. Each `overview` / `window` call creates a new `capture_id`. Crops always reference a specific capture so there are no collisions between sessions.

## Token Budget

| Call | Dimensions | Tokens |
|------|-----------|--------|
| Overview | 1200x675 | ~1,080 |
| Typical crop | 1568xN | 200–1,800 |
| Overview + 1 crop | — | ~1,300–2,900 |
| **Window (content region)** | **1568xN** | **~1,000–1,500** |
| **Window + window-crop** | — | **~1,000–2,000** |
| Ambiguous response (no image) | — | ~150 |

## Cleanup

Temp full-res captures older than 1 hour are automatically purged on each run.

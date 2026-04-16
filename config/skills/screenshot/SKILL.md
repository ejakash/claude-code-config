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

## Workflow

1. Run `overview`, read the saved image
2. Analyze — if any area needs more detail, estimate percentage coordinates
3. Run `crop` with those coordinates **and the capture_id from step 1**
4. Repeat for additional regions as needed

Multiple captures can coexist. Each overview creates a new `capture_id`. Crops always reference a specific capture so there are no collisions between sessions.

## Token Budget

| What | Dimensions | Tokens |
|------|-----------|--------|
| Overview | 1200x675 | ~1,080 |
| Typical crop | 1568xN | 200–1,800 |
| Overview + 1 crop | — | ~1,300–2,900 |

## Cleanup

Temp full-res captures older than 1 hour are automatically purged on each run.

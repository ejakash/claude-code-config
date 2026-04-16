# CHANGELOG-2026-04-15-initial-baseline

**Date:** 2026-04-15
**Tag:** [core]
**Summary:** Initial capture of personal PC Claude Code configuration as the project baseline.

## Goal

Establish a reference snapshot of the personal PC's `~/.claude/` setup so it can be selectively applied to other machines (work PC, future machines).

## What Was Captured

Source machine: personal PC (WSL username: `pudge`, Windows username: `spirit`, timezone: `America/Chicago`).

Files captured into `config/`:

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Global agent instructions: STT guidance, tool preferences, command hygiene, screenshot path |
| `settings.json` | Permissions allow-list, hooks config, plugins (superpowers, LSP), statusLine, model (haiku) |
| `hooks/pretooluse-bash-guardrails.py` | Rewrites `cd && git` compounds; denies cat/grep/find/xargs/python -c in favor of built-in tools |
| `hooks/check-cs-edit.py` | Reminds agent to run ReSharper inspectcode after editing .cs files |
| `rules/dotnet.md` | .NET navigation, build/test conventions, ReSharper CLI usage with parse-sarif.py |
| `rules/python.md` | Python LSP, venv awareness, no python -c |
| `rules/frontend.md` | TypeScript/React LSP, npm scripts, absolute paths |
| `scripts/parse-sarif.py` | Parses JetBrains inspectcode SARIF output, filters generated files |
| `skills/screenshot/SKILL.md` | Proactive screenshot skill (overview + crop workflow) |
| `skills/screenshot/capture.ps1` | PowerShell script for WSL→Windows screen capture |
| `statusline-command.sh` | Two-line Tokyo Night status bar: model, tokens, context, cost, rate limits |

## Machine-Specific Values

The following values in `config/` are marked with `# <-- edit per machine` and must be adapted when applying to a different machine:

| File | Value | Current (personal PC) |
|------|-------|-----------------------|
| `settings.json` | Hook command paths | `/home/pudge/` |
| `settings.json` | statusLine command path | `/home/pudge/` |
| `CLAUDE.md` | Screenshot folder path | `spirit` (Windows username) |
| `rules/dotnet.md` | jb.exe path (×4 occurrences) | `spirit` (Windows username) |
| `statusline-command.sh` | TZ= timezone (×4 occurrences) | `America/Chicago` |

## What Was NOT Captured

Intentionally excluded (runtime state, not config):
- `history.jsonl` — conversation history
- `sessions/`, `projects/`, `tasks/`, `plans/` — ephemeral state
- `plugins/` — marketplace cache (re-downloaded automatically)
- `memory/` — project-specific memories
- `.credentials.json`, `mcp-needs-auth-cache.json` — auth tokens
- `cache/`, `telemetry/`, `paste-cache/`, `downloads/` — runtime dirs

## Deployment (applying to a new machine)

When applying this baseline to a machine for the first time:

1. Establish machine identity — ask for:
   - `WSL_USER` (e.g. `pudge`) — appears in hook paths and statusLine in `settings.json`
   - `WIN_USER` (e.g. `spirit`) — appears in `rules/dotnet.md` and `CLAUDE.md`
   - `TIMEZONE` (e.g. `America/Chicago`) — appears in `statusline-command.sh`

2. For each file, compare `config/<file>` against the machine's `~/.claude/<file>` and merge selectively — do NOT overwrite blindly.

3. For files that don't yet exist on the machine, copy and substitute:
   ```bash
   sed 's|/home/pudge/|/home/WSL_USER/|g' config/settings.json > ~/.claude/settings.json
   sed 's|spirit|WIN_USER|g' config/CLAUDE.md > ~/.claude/CLAUDE.md
   sed 's|spirit|WIN_USER|g' config/rules/dotnet.md > ~/.claude/rules/dotnet.md
   sed 's|America/Chicago|TIMEZONE|g' config/statusline-command.sh > ~/.claude/statusline-command.sh
   chmod +x ~/.claude/statusline-command.sh
   ```
   Remaining files (hooks, scripts, skills, python/frontend rules) copy directly without substitution.

## Verification

- Launch Claude Code — status bar should render with two lines (model, tokens, rate limits)
- Edit any `.cs` file — should trigger inspectcode reminder
- Run a `cat` or `grep` bash command — pretooluse hook should deny it and suggest built-in tools

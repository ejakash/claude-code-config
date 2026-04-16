# CLAUDE.md

> This mirrors `AGENTS.md` (the primary source) for Claude Code compatibility. Keep both files in sync.

## What This Repo Is

A curated reference for Claude Code (`~/.claude/`) configuration, shared across machines (personal and work PCs). It is **not a deployment pipeline** — nothing gets overwritten without explicit user confirmation.

The repo holds proven, refined settings. Changes bake on a live machine for a day or two first, then get contributed here. Other machines selectively adopt changes when ready.

## Core Principle: Merge, Not Overwrite

When applying any change from this repo to a machine, or contributing a machine's change to this repo:

- **Never copy files wholesale** without reviewing what's already there
- **Always compare** `config/` (project) vs `~/.claude/` (machine) and present differences
- **The user decides** what to adopt — for each diff, present it with a recommendation
- **Path substitution** is the agent's job at apply time — ask for `YOUR_WSL_USER` and `YOUR_WIN_USER` when needed

## File Structure

```
AGENTS.md / CLAUDE.md       — this file (agent instructions for this repo)
SETUP-GUIDE.md              — how to bootstrap a fresh machine
CHANGELOG-SUMMARY.md        — index of all changelogs
changelogs/                 — one file per change (CHANGELOG-YYYY-MM-DD-title.md)
.changelog-status           — local per-machine reviewed-changelog list (git-ignored)
config/                     — curated reference; mirrors ~/.claude/ layout
  CLAUDE.md                 — global instructions
  settings.json             — permissions, hooks, plugins, model
  hooks/                    — PreToolUse / PostToolUse hook scripts
  rules/                    — language-specific guidance files
  scripts/                  — utility scripts (parse-sarif.py, etc.)
  skills/                   — custom skill definitions
  statusline-command.sh     — status bar script
```

`config/` mirrors the `~/.claude/` path layout exactly so copy paths are predictable.

## Machine-Specific Values

Files in `config/` use `# <-- edit per machine: <what>` (or `//` for JSON) to mark values that differ between machines. When applying to a new machine, ask for:

- `YOUR_WSL_USER` — WSL username (e.g. `pudge`) — appears in hook command paths and statusLine path in `settings.json`
- `YOUR_WIN_USER` — Windows username (e.g. `spirit`) — appears in `rules/dotnet.md` (jb.exe path) and `CLAUDE.md` (screenshot path)
- `YOUR_TIMEZONE` — local timezone for `statusline-command.sh` (e.g. `America/Chicago`)

Perform `sed` substitution before merging — do not commit machine-specific values.

## Changelog Tags

- **`[core]`** — agent strongly recommends on every machine; still confirms before applying
- **`[optional]`** — agent presents neutrally; recommendation depends on machine context

Both tags require user confirmation. Nothing applies automatically.

## Changelog File Format

```markdown
# CHANGELOG-YYYY-MM-DD-short-title

**Date:** YYYY-MM-DD
**Tag:** [core] or [optional]
**Summary:** One sentence describing the change.

## Goal

What problem this solves or what improvement it makes.

## Change

Exact files modified, values added/changed, with enough detail to reproduce on another machine.
Note any `<-- edit per machine` values.

## Deployment

Steps to apply this change on a new machine (agent-runnable where possible).

## Verification

How to confirm the change is working.
```

## Workflow: Making a Change (machine → project)

The user refines a change on a live machine, then asks the agent to capture it.

1. Agent reads `~/.claude/` (live) and `config/` (project) — identifies the difference
2. Agent proposes changelog content with goal, exact change, and `<-- edit per machine` markers
3. User reviews and approves
4. Agent updates `config/` to match the live state
5. Agent creates `changelogs/CHANGELOG-YYYY-MM-DD-title.md`
6. Agent updates `CHANGELOG-SUMMARY.md` (add entry at bottom)
7. Agent adds changelog filename to `.changelog-status` on this machine
8. User commits

## Workflow: Applying Changes (project → machine)

Run after `git pull` to bring a machine up to date.

1. Agent reads `.changelog-status` (reviewed list) and `CHANGELOG-SUMMARY.md` (full list)
2. Identifies changelogs not yet in `.changelog-status` — these are new
3. For each new changelog in order:
   - Agent reads the changelog and summarizes: what it does, why, relevant files
   - Presents recommendation (`[core]` = strong yes, `[optional]` = context-dependent reasoning)
   - For file changes: shows the specific diff between `config/` and `~/.claude/`
   - User: yes / no / partial
   - If yes: agent performs merge (adapts paths to this machine's values)
   - Adds changelog filename to `.changelog-status` regardless of decision
4. Done when no new changelogs remain

## Workflow: Bootstrapping a Fresh Machine

Follow `SETUP-GUIDE.md`. High level:

1. Clone repo, establish machine identity (WSL username, Windows username, timezone)
2. If Claude Code already configured: run the Apply workflow above — the agent presents each `[core]` and `[optional]` changelog for selective adoption
3. If truly fresh (no `~/.claude/`): agent walks `config/` file by file, adapts paths, applies with confirmation
4. Initialize `.changelog-status` with all existing changelog filenames marked as reviewed

## When a File Diverges Significantly Between Machines

Use suffixed copies rather than a single file with massive conditional sections:

- `rules/dotnet-personal.md` and `rules/dotnet-work.md` instead of one heavily-commented `dotnet.md`
- The changelog for each describes which to deploy to `~/.claude/rules/dotnet.md` on that machine

## Never Commit Runtime State

`.gitignore` covers it, but explicitly: `history.jsonl`, `.credentials.json`, `sessions/`, `tasks/`, `plans/`, `projects/`, `cache/`, `telemetry/`, and all other runtime dirs are never staged. Only curated files under `config/` get committed.

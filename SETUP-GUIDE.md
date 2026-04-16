# Setup Guide

How to bring a machine into the claude-code-optimizations project — either bootstrapping from scratch or syncing an existing setup.

## Prerequisites

- Claude Code installed (`claude --version` works)
- `git`, `python3` available in WSL
- This repo cloned (or clone it now):
  ```bash
  git clone git@github.com:ejakash/claude-code-config.git /mnt/d/labs/claude-code-optimizations
  ```

---

## Step 1: Establish Machine Identity

Note these values — you'll need them throughout setup:

| Variable | What it is | Example |
|----------|-----------|---------|
| `WSL_USER` | Your WSL username | `pudge` |
| `WIN_USER` | Your Windows username | `spirit` |
| `TIMEZONE` | Your local timezone (TZ format) | `America/Chicago` |

Run to confirm WSL username:
```bash
whoami
```

---

## Step 2: Choose Your Path

**Path A — Fresh machine (no `~/.claude/` config yet)**
Follow steps 3–7 to deploy the baseline, then proceed to Step 8.

**Path B — Existing machine (already has `~/.claude/` config)**
Skip to Step 8 (Apply Changelogs). The agent will compare project vs machine and merge selectively — nothing gets overwritten without your confirmation.

---

## Step 3: Deploy Config Files (Fresh Machine Only)

For each file below, the agent compares `config/<file>` against `~/.claude/<file>` and presents any differences. On a fresh machine (no existing config), files are deployed with path substitution.

### `~/.claude/CLAUDE.md`
```bash
sed 's|spirit|WIN_USER|g' \
  /mnt/d/labs/claude-code-optimizations/config/CLAUDE.md \
  > ~/.claude/CLAUDE.md
```
Review the result — the screenshot path should show your Windows username.

### `~/.claude/settings.json`
```bash
sed 's|/home/pudge/|/home/WSL_USER/|g' \
  /mnt/d/labs/claude-code-optimizations/config/settings.json \
  > ~/.claude/settings.json
```
Review: hook command paths and statusLine path should use your WSL username.

### Hook scripts (no substitution needed)
```bash
mkdir -p ~/.claude/hooks
cp /mnt/d/labs/claude-code-optimizations/config/hooks/pretooluse-bash-guardrails.py ~/.claude/hooks/
cp /mnt/d/labs/claude-code-optimizations/config/hooks/check-cs-edit.py ~/.claude/hooks/
```

### Rules
```bash
mkdir -p ~/.claude/rules
# dotnet.md needs Windows username substitution:
sed 's|spirit|WIN_USER|g' \
  /mnt/d/labs/claude-code-optimizations/config/rules/dotnet.md \
  > ~/.claude/rules/dotnet.md
# Others copy directly:
cp /mnt/d/labs/claude-code-optimizations/config/rules/python.md ~/.claude/rules/
cp /mnt/d/labs/claude-code-optimizations/config/rules/frontend.md ~/.claude/rules/
```

### Scripts
```bash
mkdir -p ~/.claude/scripts
cp /mnt/d/labs/claude-code-optimizations/config/scripts/parse-sarif.py ~/.claude/scripts/
```

### Skills
```bash
mkdir -p ~/.claude/skills/screenshot
cp /mnt/d/labs/claude-code-optimizations/config/skills/screenshot/SKILL.md ~/.claude/skills/screenshot/
cp /mnt/d/labs/claude-code-optimizations/config/skills/screenshot/capture.ps1 ~/.claude/skills/screenshot/
```

### Status line
```bash
sed 's|America/Chicago|TIMEZONE|g' \
  /mnt/d/labs/claude-code-optimizations/config/statusline-command.sh \
  > ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

---

## Step 4: Initialize `.changelog-status`

Mark all existing changelogs as reviewed so you only see future changes on sync:

```bash
grep -oP '\(\Kchangelogs/[^)]+' \
  /mnt/d/labs/claude-code-optimizations/CHANGELOG-SUMMARY.md \
  | xargs -I{} basename {} \
  > /mnt/d/labs/claude-code-optimizations/.changelog-status
```

Or manually create `.changelog-status` with each changelog filename (one per line):
```
CHANGELOG-2026-04-15-initial-baseline.md
```

---

## Step 5: Verify

Launch Claude Code in any project:
- Status bar should render (two-line Tokyo Night display with model, tokens, rate limits)
- Edit a `.cs` file → should show inspectcode reminder
- Run `cat somefile` in a Claude Code bash call → pretooluse hook should deny it

---

## Step 8: Apply Changelogs (Sync Workflow)

Run this whenever you `git pull` to bring the machine up to date.

1. `git -C /mnt/d/labs/claude-code-optimizations pull`
2. Ask the agent: *"Look at this project's CHANGELOG-SUMMARY.md and my `.changelog-status`. What's new? Walk me through each new change."*
3. For each new changelog, the agent will:
   - Summarize what it does and why
   - Show the relevant diff between `config/` and your `~/.claude/`
   - Give a recommendation
   - Ask: yes / no / partial?
   - If yes: perform the merge, adapting paths to your machine
   - Mark the changelog in `.changelog-status` either way

---

## Contributing a Change Back

When you've refined a change on this machine and want to share it:

Tell the agent: *"I've been using [description] for a few days and like it. Add it to the project."*

The agent will:
1. Diff your `~/.claude/` against `config/`
2. Identify the change
3. Propose a changelog entry
4. Update `config/` to match your machine's state (with `<-- edit per machine` markers where needed)
5. Create `changelogs/CHANGELOG-YYYY-MM-DD-title.md`
6. Update `CHANGELOG-SUMMARY.md`
7. Add to `.changelog-status`

Then commit and push so other machines can pick it up.

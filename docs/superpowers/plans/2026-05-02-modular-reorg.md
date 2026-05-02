# Modular Reorg Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure `claude-code-optimizations` and `wezterm` repos into module-folder layouts. Extract cross-cutting tools (`claude-waiting-notification`, `auto-screenshot`) into their own sibling repos under `/mnt/d/labs/`. Replace the event-sourcing changelog meta with a per-machine `synced-on-<hostname>` git-tag sync model. Drop the bash-guardrails hook, check-cs-edit hook, dotnet/python/frontend rules, and `parse-sarif.py`.

**Architecture:** Five repos. Each baseline has top-level `setup.md` + `README.md` + `CLAUDE.md` + module folders. Cross-cutting repos use the same shape at root. Each module: `README.md` + `setup.md` + files. Sync uses a machine-local movable git tag — robust to user-driven `git pull` outside the agent.

**Tech Stack:** git (per-repo, cross-repo file moves via copy + delete with attribution), markdown (READMEs/setup.md), shell-based verification (no test framework — checks are file existence, JSON parse, grep).

**Spec:** `docs/superpowers/specs/2026-05-02-modular-reorg-design.md`

**Migration adapts TDD as "verify-before, change, verify-after":**
- Step 1: assert the destination state does *not* yet match expected.
- Step 2: make the change.
- Step 3: assert the destination state *does* match expected.
- Step 4: commit.

---

## Phase A: Restructure `claude-code-optimizations`

### Task A1: Cut migration branch

**Files:** none (git branch operation)

- [ ] **Step 1: Verify clean working tree on `main`**

Run: `git -C /mnt/d/labs/claude-code-optimizations status --short`
Expected: empty output (no uncommitted changes). If output is non-empty, stash or commit before proceeding.

- [ ] **Step 2: Cut branch `reorg/modular-layout`**

Run: `git -C /mnt/d/labs/claude-code-optimizations checkout -b reorg/modular-layout`
Expected: `Switched to a new branch 'reorg/modular-layout'`.

- [ ] **Step 3: Confirm branch**

Run: `git -C /mnt/d/labs/claude-code-optimizations branch --show-current`
Expected: `reorg/modular-layout`.

---

### Task A2: Create `baseline-settings/` module

**Files:**
- Create: `baseline-settings/README.md`
- Create: `baseline-settings/setup.md`
- Create: `baseline-settings/settings.json` (moved+slimmed from `config/settings.json`)

- [ ] **Step 1: Verify destination does not exist**

Run: `ls /mnt/d/labs/claude-code-optimizations/baseline-settings 2>&1`
Expected: `ls: cannot access ...: No such file or directory`.

- [ ] **Step 2: Read source `config/settings.json`**

Read: `/mnt/d/labs/claude-code-optimizations/config/settings.json`. Note the four hook entries that will be dropped:
- `PostToolUse` matcher `Write|Edit` running `check-cs-edit.py`
- `PreToolUse` matcher `Bash` running `pretooluse-bash-guardrails.py`
- `Stop` running `notify-waiting.sh 1` (moves to claude-waiting-notification in Phase B)
- `UserPromptSubmit` running `notify-waiting.sh 0` (moves to claude-waiting-notification in Phase B)

The `agent-deck hook-handler` entries on `Notification`, `PermissionRequest`, `PreCompact`, `SessionEnd`, `SessionStart`, `Stop`, `UserPromptSubmit` stay (out of scope per spec).

- [ ] **Step 3: Create `baseline-settings/settings.json` (slimmed)**

Create the new file with all `agent-deck` entries preserved verbatim and the four dropped entries removed. After this step, the `Stop` and `UserPromptSubmit` arrays should each contain *only* the `agent-deck` hook (one entry each), and the `PostToolUse` and `PreToolUse` keys should be gone entirely (they had no other hooks). Keep `permissions`, `statusLine`, `enabledPlugins`, `extraKnownMarketplaces`, `autoUpdatesChannel`, `skipDangerousModePermissionPrompt`, `model` unchanged.

- [ ] **Step 4: Verify the slimmed JSON parses**

Run: `python3 -c "import json; json.load(open('/mnt/d/labs/claude-code-optimizations/baseline-settings/settings.json'))"`
Expected: no output (clean parse).

- [ ] **Step 5: Verify the four dropped entries are gone**

Run: `grep -E 'pretooluse-bash-guardrails|check-cs-edit|notify-waiting' /mnt/d/labs/claude-code-optimizations/baseline-settings/settings.json`
Expected: empty output.

- [ ] **Step 6: Verify `agent-deck` entries survived**

Run: `grep -c 'agent-deck' /mnt/d/labs/claude-code-optimizations/baseline-settings/settings.json`
Expected: `7` (Notification, PermissionRequest, PreCompact, SessionEnd, SessionStart, Stop, UserPromptSubmit).

- [ ] **Step 7: Write `baseline-settings/README.md`**

Content (one short page):

```markdown
# baseline-settings

Claude Code's `~/.claude/settings.json` baseline: permissions allow-list, plugins, statusLine pointer, model default, plus the `agent-deck` notification hooks.

Does **not** include hooks for cross-cutting tools (those ship in their own repos — see `claude-waiting-notification` and `auto-screenshot`). On a fresh machine, install this module first; cross-cutting modules merge their own hook entries on top.

See `setup.md` for install steps.
```

- [ ] **Step 8: Write `baseline-settings/setup.md`**

Content:

````markdown
# baseline-settings — setup

**Requires:** Claude Code

## Per-machine values

- `<WSL_USER>` — your WSL username (appears in `statusLine.command` path)

## Files

- `settings.json` → deploys to `~/.claude/settings.json` (merge if file exists; do not overwrite blindly)

## Install

1. If `~/.claude/settings.json` does not exist: copy this module's `settings.json` after substituting `<WSL_USER>` (sed `s|/home/pudge/|/home/<WSL_USER>/|g`).
2. If `~/.claude/settings.json` exists: merge keys. The user's existing entries take precedence on conflicts; ask before overwriting any keys that already have a value.
3. Confirm `python3 -c "import json; json.load(open('~/.claude/settings.json'.replace('~', '$HOME')))"` parses cleanly.

## Verify

- `claude --version` runs without errors.
- Status bar renders (the `statusline-command.sh` deployed by the `statusline` module).
- Permissions allow-list applies (e.g. `git status` doesn't prompt).

## Uninstall

Remove the keys this module added; restore the user's prior `~/.claude/settings.json` from backup if available.
````

- [ ] **Step 9: Stage and commit**

```bash
git -C /mnt/d/labs/claude-code-optimizations add baseline-settings/
git -C /mnt/d/labs/claude-code-optimizations commit -m "reorg: create baseline-settings/ module (slimmed settings.json)"
```

---

### Task A3: Create `statusline/` module

**Files:**
- Create: `statusline/README.md`
- Create: `statusline/setup.md`
- Create: `statusline/statusline-command.sh` (moved from `config/statusline-command.sh`)

- [ ] **Step 1: Verify destination does not exist**

Run: `ls /mnt/d/labs/claude-code-optimizations/statusline 2>&1`
Expected: `No such file or directory`.

- [ ] **Step 2: Move file**

```bash
mkdir -p /mnt/d/labs/claude-code-optimizations/statusline
git -C /mnt/d/labs/claude-code-optimizations mv config/statusline-command.sh statusline/statusline-command.sh
```

- [ ] **Step 3: Verify source gone, dest present**

Run: `ls /mnt/d/labs/claude-code-optimizations/config/statusline-command.sh 2>&1; ls /mnt/d/labs/claude-code-optimizations/statusline/statusline-command.sh`
Expected: first command errors (`No such file`); second prints the path.

- [ ] **Step 4: Write `statusline/README.md`**

```markdown
# statusline

Two-line Tokyo Night status bar for Claude Code: model, tokens, context, cost, rate limits.

Wired into `~/.claude/settings.json` via the `statusLine.command` field — the `baseline-settings` module already points there, so install order matters (statusline before baseline-settings, OR install statusline first and have baseline-settings reference it).
```

- [ ] **Step 5: Write `statusline/setup.md`**

````markdown
# statusline — setup

**Requires:** Claude Code, bash

## Per-machine values

- `<WSL_USER>` — your WSL username (appears in `~/.claude/settings.json` `statusLine.command`, not in this script itself)
- `<TIMEZONE>` — your local TZ (e.g. `America/Chicago`); appears 4 times in `statusline-command.sh`

## Files

- `statusline-command.sh` → deploys to `~/.claude/statusline-command.sh` (chmod +x)

## Install

1. `cp statusline-command.sh ~/.claude/statusline-command.sh`
2. Substitute `<TIMEZONE>` (sed `s|America/Chicago|<TIMEZONE>|g ~/.claude/statusline-command.sh`).
3. `chmod +x ~/.claude/statusline-command.sh`
4. Confirm `~/.claude/settings.json` `statusLine.command` references `bash /home/<WSL_USER>/.claude/statusline-command.sh`. (`baseline-settings` does this by default.)

## Verify

Launch Claude Code in any directory. The status bar should render two lines (model + tokens line, rate-limits line) at the bottom.
````

- [ ] **Step 6: Stage and commit**

```bash
git -C /mnt/d/labs/claude-code-optimizations add statusline/
git -C /mnt/d/labs/claude-code-optimizations commit -m "reorg: create statusline/ module"
```

---

### Task A4: Create `claude-md/` module

**Files:**
- Create: `claude-md/README.md`
- Create: `claude-md/setup.md`
- Create: `claude-md/CLAUDE.md` (moved from `config/CLAUDE.md`)

- [ ] **Step 1: Verify destination does not exist**

Run: `ls /mnt/d/labs/claude-code-optimizations/claude-md 2>&1`
Expected: `No such file or directory`.

- [ ] **Step 2: Move file**

```bash
mkdir -p /mnt/d/labs/claude-code-optimizations/claude-md
git -C /mnt/d/labs/claude-code-optimizations mv config/CLAUDE.md claude-md/CLAUDE.md
```

- [ ] **Step 3: Write `claude-md/README.md`**

```markdown
# claude-md

Global agent instructions installed to `~/.claude/CLAUDE.md`. Covers speech-to-text input quirks, tool-usage preferences (Read/Edit/Grep over Bash equivalents), command hygiene (no compound `cd && cmd`), screenshot folder convention, and a pointer to language-specific rules.

These instructions are loaded on every session in every project. Keep them generic and short — project-specific rules belong in each project's own `CLAUDE.md`.
```

- [ ] **Step 4: Write `claude-md/setup.md`**

````markdown
# claude-md — setup

**Requires:** Claude Code

## Per-machine values

- `<WIN_USER>` — your Windows username; appears in the screenshot folder path inside this `CLAUDE.md`.

## Files

- `CLAUDE.md` → deploys to `~/.claude/CLAUDE.md` (merge if file exists; do not overwrite blindly).

## Install

1. If `~/.claude/CLAUDE.md` does not exist: `sed 's|spirit|<WIN_USER>|g' CLAUDE.md > ~/.claude/CLAUDE.md`
2. If it exists: merge sections. Sections in this module that are absent from the user's existing file get appended; conflicts get presented to the user.

## Verify

Start a Claude Code session. Confirm the agent honors STT substitutions ("cloud code" → Claude Code), prefers Read/Edit/Grep, and avoids `cd && cmd` compounds.
````

- [ ] **Step 5: Stage and commit**

```bash
git -C /mnt/d/labs/claude-code-optimizations add claude-md/
git -C /mnt/d/labs/claude-code-optimizations commit -m "reorg: create claude-md/ module"
```

---

### Task A5: Write top-level `setup.md` (orchestration)

**Files:**
- Create: `setup.md` (top-level)

- [ ] **Step 1: Verify it does not yet exist**

Run: `ls /mnt/d/labs/claude-code-optimizations/setup.md 2>&1`
Expected: `No such file or directory`.

- [ ] **Step 2: Write the orchestration setup.md**

Content:

````markdown
# Setup — `claude-code-optimizations`

This repo holds Claude Code configuration as independently-installable modules. The agent walks the module list with you and installs only what you want.

## Per-machine values (collected once up front)

- `<WSL_USER>` — your WSL username (e.g. `pudge`)
- `<WIN_USER>` — your Windows username (e.g. `spirit`)
- `<TIMEZONE>` — your local TZ (e.g. `America/Chicago`)

## Modules

| Module | What it does | Requires |
|---|---|---|
| `baseline-settings/` | `~/.claude/settings.json` baseline (permissions, plugins, model, statusline pointer, agent-deck hooks) | Claude Code |
| `statusline/` | Two-line Tokyo Night status bar | Claude Code, bash |
| `claude-md/` | Global agent instructions in `~/.claude/CLAUDE.md` | Claude Code |

**Ordering:** install `baseline-settings` and `statusline` before any cross-cutting module that registers hooks in `settings.json` (e.g. `claude-waiting-notification`).

## See also (cross-cutting tools)

- **claude-waiting-notification** — Stop-hook + WezTerm Lua + Windows toast for idle Claude Code sessions. Requires WSL2 + WezTerm + Win11.
  `<TBD: github URL once published>`
- **auto-screenshot** — Window-aware screen capture skill for Windows hosts. Requires Windows + PowerShell.
  `<TBD: github URL once published>`
- **spawn-session** — Fan a batch of independent tasks into N Claude Code processes, each in its own WezTerm pane. Requires WezTerm + Claude Code.
  `<TBD: github URL once published>`

## Sync

After `git pull`, ask the agent to "sync" / "update" this repo. Sync state is a machine-local git tag `synced-on-<hostname>`:

- Tag exists → agent shows `git log synced-on-<hostname>..HEAD --stat`, walks per-module deltas, applies what you accept, then `git tag -f synced-on-<hostname>` at HEAD.
- Tag missing (fresh clone) → agent treats as fresh setup and walks the module menu above.

The tag is local-only (tags don't push by default). User-driven `git pull` outside the agent is fine — the tag still points at the last commit you actually synced.
````

- [ ] **Step 3: Stage and commit**

```bash
git -C /mnt/d/labs/claude-code-optimizations add setup.md
git -C /mnt/d/labs/claude-code-optimizations commit -m "reorg: top-level setup.md (orchestration menu)"
```

---

### Task A6: Rewrite top-level `README.md`

**Files:**
- Create: `README.md` (top-level — does not exist today)

- [ ] **Step 1: Verify it does not yet exist**

Run: `ls /mnt/d/labs/claude-code-optimizations/README.md 2>&1`
Expected: `No such file or directory`.

- [ ] **Step 2: Write `README.md`**

```markdown
# claude-code-optimizations

Curated Claude Code (`~/.claude/`) configuration, installable as independent modules. Companion to the sibling `wezterm/` repo and several cross-cutting tool repos (see Setup).

## Quick start

Read `setup.md`. The agent walks the module menu with you on a fresh machine; on an existing machine, ask it to "sync" after `git pull`.

## Modules

- `baseline-settings/` — `settings.json` baseline
- `statusline/` — two-line Tokyo Night status bar
- `claude-md/` — global agent instructions

Cross-cutting tools (own repos): `claude-waiting-notification`, `auto-screenshot`, `spawn-session`. See `setup.md` "See also" for links.
```

- [ ] **Step 3: Stage and commit**

```bash
git -C /mnt/d/labs/claude-code-optimizations add README.md
git -C /mnt/d/labs/claude-code-optimizations commit -m "reorg: top-level README"
```

---

### Task A7: Rewrite top-level `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md` (replace existing content)

- [ ] **Step 1: Verify current content is the old workflow doc**

Run: `head -3 /mnt/d/labs/claude-code-optimizations/CLAUDE.md`
Expected: contains "What This Repo Is" or similar — i.e., the old workflow doc.

- [ ] **Step 2: Replace `CLAUDE.md` with the new slim version**

Content:

````markdown
# CLAUDE.md — agent instructions for working in this repo

## What this repo is

Module-style configuration for Claude Code (`~/.claude/`). Each top-level folder is one self-contained module. Cross-cutting tools live in their own sibling repos under `/mnt/d/labs/` — see `setup.md` "See also."

## Module shape

Every module folder has:

```
<module>/
  README.md     human-facing intro
  setup.md      install instructions; agent reads + acts
  <files>       the actual config / scripts / skill files
```

`setup.md` is free prose. By soft convention each one carries a `**Requires:**` line (deps), a `## Per-machine values` section (substitution markers), a `## Files` section (where each file deploys), and `## Install` / `## Verify` steps.

## Sync model — `synced-on-<hostname>` git tag

Per-machine, per-repo, machine-local. Tags don't push by default.

When the user says "sync" or "update":

1. `git tag --list 'synced-on-$(hostname)'` — exists?
   - **Yes** → use as baseline, regardless of who ran the last `git pull`.
   - **No** → fresh-setup flow: walk `setup.md` module menu.
2. `git log <tag>..HEAD --stat` for the delta. Group by module folder. Walk per module.
3. Per module, `git diff <tag>..HEAD -- <module>/`. Recommend, ask user yes/no/partial, apply, adapt paths/values.
4. **Module deletion case:** if a module folder was removed upstream, surface "remove from this machine?" — do not silently leave stale files.
5. On completion, `git tag -f synced-on-$(hostname)` at HEAD. Advance even on partial accept; declined modules don't auto-re-offer.

Fallbacks if the tag is missing: `ORIG_HEAD` after a fresh pull, `git reflog`, or ask the user "what's the last commit you synced?"

## Per-machine values

Files in modules use literal source-machine values (e.g. `pudge`, `spirit`, `America/Chicago`) with `<-- edit per machine: <what>` markers (or `// edit per machine: <what>` in JSON). The agent substitutes at deploy time.

## Adding a new module

1. Create `<new-module>/` folder.
2. Add `README.md` + `setup.md` (use neighbors as a template — Cat-1 free prose).
3. Drop files in.
4. Update top-level `setup.md` module table.
5. Commit. Other machines pick it up on next sync.

## Removing a module

Just `git rm -r <module>/`. The sync model handles cleanup on other machines (step 4 of sync above).
````

- [ ] **Step 3: Verify replacement**

Run: `grep -c 'synced-on-' /mnt/d/labs/claude-code-optimizations/CLAUDE.md`
Expected: `>= 2`.

Run: `grep -c 'event-sourcing\|changelog' /mnt/d/labs/claude-code-optimizations/CLAUDE.md`
Expected: `0` (the old workflow language is gone).

- [ ] **Step 4: Stage and commit**

```bash
git -C /mnt/d/labs/claude-code-optimizations add CLAUDE.md
git -C /mnt/d/labs/claude-code-optimizations commit -m "reorg: rewrite CLAUDE.md for module-folder layout + tag-based sync"
```

---

### Task A8: Delete dropped files (Phase A scope only — keep cross-cutting subtrees)

**Files:**
- Delete: `CHANGELOG-SUMMARY.md`
- Delete: `SETUP-GUIDE.md`
- Delete: `config/rules/` (entire folder)
- Delete: `config/scripts/parse-sarif.py` (and `config/scripts/` if empty after)
- Delete: `config/hooks/pretooluse-bash-guardrails.py`
- Delete: `config/hooks/check-cs-edit.py`

**Stays (extracted in Phases B and C):** `config/hooks/notify-waiting.sh`, `config/windows-helpers/`, `config/skills/screenshot/`. Also stays for now: `changelogs/`, `docs/superpowers/`, `AUDIT-PROMPT-notification-system.md` (handled in Phases B, C, E).

- [ ] **Step 1: Verify which files are about to be deleted**

```bash
ls /mnt/d/labs/claude-code-optimizations/CHANGELOG-SUMMARY.md \
   /mnt/d/labs/claude-code-optimizations/SETUP-GUIDE.md \
   /mnt/d/labs/claude-code-optimizations/config/rules/ \
   /mnt/d/labs/claude-code-optimizations/config/scripts/parse-sarif.py \
   /mnt/d/labs/claude-code-optimizations/config/hooks/pretooluse-bash-guardrails.py \
   /mnt/d/labs/claude-code-optimizations/config/hooks/check-cs-edit.py
```
Expected: all paths exist (no errors).

- [ ] **Step 2: `git rm` each path**

```bash
cd /mnt/d/labs/claude-code-optimizations
git rm CHANGELOG-SUMMARY.md SETUP-GUIDE.md
git rm -r config/rules/
git rm config/scripts/parse-sarif.py
# config/scripts/ is empty after — `git rm` handles dir removal automatically
git rm config/hooks/pretooluse-bash-guardrails.py config/hooks/check-cs-edit.py
```

- [ ] **Step 3: Verify cross-cutting subtrees survived**

```bash
ls /mnt/d/labs/claude-code-optimizations/config/hooks/notify-waiting.sh \
   /mnt/d/labs/claude-code-optimizations/config/windows-helpers \
   /mnt/d/labs/claude-code-optimizations/config/skills/screenshot
```
Expected: all paths exist.

- [ ] **Step 4: Verify dropped files are gone**

```bash
ls /mnt/d/labs/claude-code-optimizations/CHANGELOG-SUMMARY.md \
   /mnt/d/labs/claude-code-optimizations/SETUP-GUIDE.md \
   /mnt/d/labs/claude-code-optimizations/config/rules \
   /mnt/d/labs/claude-code-optimizations/config/scripts/parse-sarif.py \
   /mnt/d/labs/claude-code-optimizations/config/hooks/pretooluse-bash-guardrails.py \
   /mnt/d/labs/claude-code-optimizations/config/hooks/check-cs-edit.py 2>&1 | grep -c 'No such file'
```
Expected: `6`.

- [ ] **Step 5: Commit**

```bash
git -C /mnt/d/labs/claude-code-optimizations commit -m "reorg: drop unused hooks (bash-guardrails, check-cs-edit), dotnet/python/frontend rules, parse-sarif, old SETUP-GUIDE + CHANGELOG-SUMMARY"
```

---

### Task A9: Phase A end-state verification

**Files:** none (verification only)

- [ ] **Step 1: Verify new module folders exist**

```bash
ls -d /mnt/d/labs/claude-code-optimizations/baseline-settings \
      /mnt/d/labs/claude-code-optimizations/statusline \
      /mnt/d/labs/claude-code-optimizations/claude-md
```
Expected: all three directories listed.

- [ ] **Step 2: Each module has README + setup**

```bash
for m in baseline-settings statusline claude-md; do
  ls /mnt/d/labs/claude-code-optimizations/$m/README.md /mnt/d/labs/claude-code-optimizations/$m/setup.md
done
```
Expected: 6 file paths printed, no errors.

- [ ] **Step 3: Top-level docs in place**

```bash
ls /mnt/d/labs/claude-code-optimizations/setup.md \
   /mnt/d/labs/claude-code-optimizations/README.md \
   /mnt/d/labs/claude-code-optimizations/CLAUDE.md
```
Expected: all three.

- [ ] **Step 4: Cross-cutting subtrees still present (will move out in Phases B/C)**

```bash
ls /mnt/d/labs/claude-code-optimizations/config/hooks/notify-waiting.sh \
   /mnt/d/labs/claude-code-optimizations/config/windows-helpers/claude-waiting.lua \
   /mnt/d/labs/claude-code-optimizations/config/windows-helpers/wezterm-claude-notify.ps1 \
   /mnt/d/labs/claude-code-optimizations/config/windows-helpers/preflight.ps1 \
   /mnt/d/labs/claude-code-optimizations/config/skills/screenshot/SKILL.md \
   /mnt/d/labs/claude-code-optimizations/config/skills/screenshot/capture.ps1
```
Expected: all paths exist.

- [ ] **Step 5: `changelogs/` still present (deferred to Phase E)**

Run: `ls -d /mnt/d/labs/claude-code-optimizations/changelogs`
Expected: directory listed.

---

### Task A10: Merge Phase A to main

- [ ] **Step 1: Review log**

Run: `git -C /mnt/d/labs/claude-code-optimizations log main..reorg/modular-layout --oneline`
Expected: 7 commits (one per Task A2-A8). Each prefixed `reorg:`.

- [ ] **Step 2: Switch to main and merge**

```bash
git -C /mnt/d/labs/claude-code-optimizations checkout main
git -C /mnt/d/labs/claude-code-optimizations merge --no-ff reorg/modular-layout -m "reorg: Phase A — module-folder layout for claude-code-optimizations"
```

- [ ] **Step 3: Verify main is updated**

Run: `git -C /mnt/d/labs/claude-code-optimizations log main --oneline | head -10`
Expected: top commit is the merge; tasks A2-A8 below it.

- [ ] **Step 4: Set personal-PC `synced-on-<hostname>` tag at this commit**

```bash
git -C /mnt/d/labs/claude-code-optimizations tag -f synced-on-$(hostname)
git -C /mnt/d/labs/claude-code-optimizations tag --list "synced-on-*"
```
Expected: tag listed.

---

## Phase B: Extract `claude-waiting-notification` repo

### Task B1: Initialize new repo

**Files:**
- Create: `/mnt/d/labs/claude-waiting-notification/` (new git repo)

- [ ] **Step 1: Verify destination doesn't exist**

Run: `ls /mnt/d/labs/claude-waiting-notification 2>&1`
Expected: `No such file or directory`.

- [ ] **Step 2: Create and init**

```bash
mkdir -p /mnt/d/labs/claude-waiting-notification
git -C /mnt/d/labs/claude-waiting-notification init
git -C /mnt/d/labs/claude-waiting-notification config user.email ejakash1992@gmail.com
git -C /mnt/d/labs/claude-waiting-notification config user.name "Akash Johny"
```

- [ ] **Step 3: Verify init**

Run: `git -C /mnt/d/labs/claude-waiting-notification status`
Expected: "On branch main" (or master), no commits, working tree clean.

---

### Task B2: Copy files from `claude-code-optimizations`

**Files:**
- Copy: `config/hooks/notify-waiting.sh` → `claude-waiting-notification/notify-waiting.sh`
- Copy: `config/windows-helpers/claude-waiting.lua` → `claude-waiting-notification/claude-waiting.lua`
- Copy: `config/windows-helpers/wezterm-claude-notify.ps1` → `claude-waiting-notification/wezterm-claude-notify.ps1`
- Copy: `config/windows-helpers/preflight.ps1` → `claude-waiting-notification/preflight.ps1`
- Copy: `changelogs/CHANGELOG-2026-04-16-claude-waiting-notification.md` → `claude-waiting-notification/docs/changelog-original.md`
- Copy: `docs/superpowers/specs/2026-04-15-claude-waiting-notification-design.md` → `claude-waiting-notification/docs/specs/2026-04-15-design.md`
- Copy: `docs/superpowers/plans/2026-04-16-claude-waiting-notification.md` → `claude-waiting-notification/docs/plans/2026-04-16-implementation.md`
- Copy: `AUDIT-PROMPT-notification-system.md` → `claude-waiting-notification/docs/audit-prompt.md`

- [ ] **Step 1: Copy script + config files (flat at root)**

```bash
SRC=/mnt/d/labs/claude-code-optimizations
DST=/mnt/d/labs/claude-waiting-notification

cp $SRC/config/hooks/notify-waiting.sh $DST/notify-waiting.sh
cp $SRC/config/windows-helpers/claude-waiting.lua $DST/claude-waiting.lua
cp $SRC/config/windows-helpers/wezterm-claude-notify.ps1 $DST/wezterm-claude-notify.ps1
cp $SRC/config/windows-helpers/preflight.ps1 $DST/preflight.ps1
chmod +x $DST/notify-waiting.sh
```

- [ ] **Step 2: Copy historical docs into `docs/`**

```bash
mkdir -p $DST/docs/specs $DST/docs/plans
cp $SRC/changelogs/CHANGELOG-2026-04-16-claude-waiting-notification.md $DST/docs/changelog-original.md
cp $SRC/docs/superpowers/specs/2026-04-15-claude-waiting-notification-design.md $DST/docs/specs/2026-04-15-design.md
cp $SRC/docs/superpowers/plans/2026-04-16-claude-waiting-notification.md $DST/docs/plans/2026-04-16-implementation.md
cp $SRC/AUDIT-PROMPT-notification-system.md $DST/docs/audit-prompt.md
```

- [ ] **Step 3: Verify all copies**

```bash
ls /mnt/d/labs/claude-waiting-notification/notify-waiting.sh \
   /mnt/d/labs/claude-waiting-notification/claude-waiting.lua \
   /mnt/d/labs/claude-waiting-notification/wezterm-claude-notify.ps1 \
   /mnt/d/labs/claude-waiting-notification/preflight.ps1 \
   /mnt/d/labs/claude-waiting-notification/docs/changelog-original.md \
   /mnt/d/labs/claude-waiting-notification/docs/specs/2026-04-15-design.md \
   /mnt/d/labs/claude-waiting-notification/docs/plans/2026-04-16-implementation.md \
   /mnt/d/labs/claude-waiting-notification/docs/audit-prompt.md
```
Expected: 8 paths printed, no errors.

---

### Task B3: Write `README.md` and `setup.md` for the new repo

**Files:**
- Create: `claude-waiting-notification/README.md`
- Create: `claude-waiting-notification/setup.md`

- [ ] **Step 1: Write `README.md`**

```markdown
# claude-waiting-notification

WezTerm-native notification when a Claude Code session goes idle. Tab amber, pane bg tint, Windows toast (real Claude icon via AUMID spoof), auto-tab-switch + window raise when backgrounded, smart suppression when user is already on the waiting pane.

**Requires:** WSL2, WezTerm on Windows 11, Claude Desktop installed (for AUMID toast icon). No-op inside tmux.

See `setup.md` for install. See `docs/` for design/plan/audit history.
```

- [ ] **Step 2: Write `setup.md`**

The content adapts the existing changelog (now at `docs/changelog-original.md`) into install-instruction shape. Source it from there — it already has the deployment steps in section 7 of the changelog. Reformat as:

````markdown
# claude-waiting-notification — setup

**Requires:** WSL2, WezTerm on Windows 11, Claude Desktop installed (for AUMID toast icon)

## Per-machine values

- `<WSL_USER>` — your WSL username
- `<WIN_USER>` — your Windows username
- `<CLAUDE_AUMID>` — Claude Desktop AppUserModelID, e.g. `Claude_pzs8sxrjxfjjc!Claude` (per-install; discover via `powershell.exe Get-StartApps | ? Name -like '*Claude*'` or run `preflight.ps1`)

## Files

| Source | Destination |
|---|---|
| `notify-waiting.sh` | `~/.claude/hooks/notify-waiting.sh` (chmod +x) |
| `claude-waiting.lua` | `C:\Users\<WIN_USER>\.wezterm-claude-waiting.lua` (edit `M.toast_script` to substitute `<WIN_USER>`) |
| `wezterm-claude-notify.ps1` | `C:\Users\<WIN_USER>\.wezterm-claude-notify.ps1` (edit AUMID to match `<CLAUDE_AUMID>`) |
| `preflight.ps1` | one-time discovery; not deployed |

## Install

1. Run `preflight.ps1` to discover this machine's `<WIN_USER>`, `<CLAUDE_AUMID>`, and WezTerm version.
2. Copy + substitute the four files per the table above.
3. Merge two hook entries into `~/.claude/settings.json`:

   ```json
   {
     "hooks": {
       "Stop": [{ "hooks": [{ "type": "command", "command": "bash /home/<WSL_USER>/.claude/hooks/notify-waiting.sh 1", "async": true }] }],
       "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "bash /home/<WSL_USER>/.claude/hooks/notify-waiting.sh 0" }] }]
     }
   }
   ```

   Append alongside any existing entries (e.g. `agent-deck hook-handler`). Both arrays merge — don't replace.

4. Wire the Lua module into `C:\Users\<WIN_USER>\.wezterm.lua` per the three touchpoints documented in `docs/changelog-original.md` § "wezterm.lua — how to wire in".
5. WezTerm auto-reloads. The first idle Claude Code event triggers the pipeline.

## Verify

See `docs/changelog-original.md` § "Verification" — six scenarios (suppression on active pane, backgrounded tab amber, different-window window-raise, click clears, Alt+N jump, prompt-submit clears).

## Uninstall

1. Remove the two `notify-waiting.sh` hook entries from `~/.claude/settings.json`.
2. Remove the `dofile`, `apply`, and `format_tab_title_overlay` integration from `.wezterm.lua`.
3. Delete `~/.claude/hooks/notify-waiting.sh`, `C:\Users\<WIN_USER>\.wezterm-claude-waiting.lua`, `C:\Users\<WIN_USER>\.wezterm-claude-notify.ps1`.
````

- [ ] **Step 3: Verify both files exist**

```bash
ls /mnt/d/labs/claude-waiting-notification/README.md /mnt/d/labs/claude-waiting-notification/setup.md
```
Expected: both listed.

---

### Task B4: Initial commit on `claude-waiting-notification`

- [ ] **Step 1: Stage all**

```bash
git -C /mnt/d/labs/claude-waiting-notification add -A
git -C /mnt/d/labs/claude-waiting-notification status --short
```
Expected: ~10 files staged (4 scripts/configs, README, setup, 4 docs).

- [ ] **Step 2: Commit**

```bash
git -C /mnt/d/labs/claude-waiting-notification commit -m "$(cat <<'EOF'
init: claude-waiting-notification (extracted from claude-code-optimizations)

WezTerm-native idle notification: tab amber, pane bg tint, Windows toast with
real Claude icon (AUMID spoof), auto-raise on backgrounded windows. Originally
shipped 2026-04-16 inside claude-code-optimizations; extracted into its own
repo as part of the modular reorg (see docs/specs/2026-04-15-design.md and
docs/changelog-original.md).
EOF
)"
```

- [ ] **Step 3: Verify single commit**

Run: `git -C /mnt/d/labs/claude-waiting-notification log --oneline`
Expected: one commit.

- [ ] **Step 4: Set sync tag**

```bash
git -C /mnt/d/labs/claude-waiting-notification tag synced-on-$(hostname)
```

---

### Task B5: Delete extracted sources from `claude-code-optimizations`

**Files:**
- Delete: `config/hooks/notify-waiting.sh`
- Delete: `config/windows-helpers/` (entire folder)
- Delete: `docs/superpowers/specs/2026-04-15-claude-waiting-notification-design.md`
- Delete: `docs/superpowers/plans/2026-04-16-claude-waiting-notification.md`
- Delete: `AUDIT-PROMPT-notification-system.md`

- [ ] **Step 1: Cut branch**

```bash
git -C /mnt/d/labs/claude-code-optimizations checkout -b reorg/extract-notification
```

- [ ] **Step 2: `git rm` each path**

```bash
cd /mnt/d/labs/claude-code-optimizations
git rm config/hooks/notify-waiting.sh
git rm -r config/windows-helpers/
git rm docs/superpowers/specs/2026-04-15-claude-waiting-notification-design.md
git rm docs/superpowers/plans/2026-04-16-claude-waiting-notification.md
git rm AUDIT-PROMPT-notification-system.md
```

- [ ] **Step 3: Verify gone**

```bash
ls /mnt/d/labs/claude-code-optimizations/config/hooks/notify-waiting.sh \
   /mnt/d/labs/claude-code-optimizations/config/windows-helpers \
   /mnt/d/labs/claude-code-optimizations/docs/superpowers/specs/2026-04-15-claude-waiting-notification-design.md \
   /mnt/d/labs/claude-code-optimizations/docs/superpowers/plans/2026-04-16-claude-waiting-notification.md \
   /mnt/d/labs/claude-code-optimizations/AUDIT-PROMPT-notification-system.md 2>&1 | grep -c 'No such file'
```
Expected: `5`.

- [ ] **Step 4: Verify `config/hooks/` is now empty (only Phase C's screenshot still under config/)**

Run: `ls /mnt/d/labs/claude-code-optimizations/config/hooks/ 2>&1`
Expected: empty output OR `No such file or directory` (if `git rm` removed the directory).

- [ ] **Step 5: Commit and merge**

```bash
git -C /mnt/d/labs/claude-code-optimizations commit -m "reorg: extract claude-waiting-notification to /mnt/d/labs/claude-waiting-notification"
git -C /mnt/d/labs/claude-code-optimizations checkout main
git -C /mnt/d/labs/claude-code-optimizations merge --no-ff reorg/extract-notification -m "reorg: Phase B — extract claude-waiting-notification"
```

- [ ] **Step 6: Advance sync tag**

```bash
git -C /mnt/d/labs/claude-code-optimizations tag -f synced-on-$(hostname)
```

---

## Phase C: Extract `auto-screenshot` repo

### Task C1: Initialize new repo

- [ ] **Step 1: Verify destination doesn't exist**

Run: `ls /mnt/d/labs/auto-screenshot 2>&1`
Expected: `No such file or directory`.

- [ ] **Step 2: Create and init**

```bash
mkdir -p /mnt/d/labs/auto-screenshot
git -C /mnt/d/labs/auto-screenshot init
git -C /mnt/d/labs/auto-screenshot config user.email ejakash1992@gmail.com
git -C /mnt/d/labs/auto-screenshot config user.name "Akash Johny"
```

---

### Task C2: Copy files from `claude-code-optimizations`

**Files:**
- Copy: `config/skills/screenshot/{SKILL.md, capture.ps1, tests/}` → `auto-screenshot/{SKILL.md, capture.ps1, tests/}`
- Copy: `changelogs/CHANGELOG-2026-04-16-smart-screenshots.md` → `auto-screenshot/docs/changelog-original.md`
- Copy: `docs/superpowers/specs/2026-04-16-smart-screenshots-design.md` → `auto-screenshot/docs/specs/2026-04-16-v1-design.md`
- Copy: `docs/superpowers/specs/2026-04-17-screenshot-v2-design.md` → `auto-screenshot/docs/specs/2026-04-17-v2-design.md`
- Copy: `docs/superpowers/specs/2026-04-17-screenshot-v2-followups.md` → `auto-screenshot/docs/specs/2026-04-17-v2-followups.md`
- Copy: `docs/superpowers/plans/2026-04-16-smart-screenshots.md` → `auto-screenshot/docs/plans/2026-04-16-v1-implementation.md`
- Copy: `docs/superpowers/plans/2026-04-17-screenshot-v2.md` → `auto-screenshot/docs/plans/2026-04-17-v2-implementation.md`

- [ ] **Step 1: Copy skill at root (flat — `SKILL.md`, `capture.ps1`, `tests/` directly under repo root)**

```bash
SRC=/mnt/d/labs/claude-code-optimizations
DST=/mnt/d/labs/auto-screenshot

cp $SRC/config/skills/screenshot/SKILL.md $DST/SKILL.md
cp $SRC/config/skills/screenshot/capture.ps1 $DST/capture.ps1
cp -r $SRC/config/skills/screenshot/tests $DST/tests
```

- [ ] **Step 2: Copy historical docs**

```bash
mkdir -p $DST/docs/specs $DST/docs/plans
cp $SRC/changelogs/CHANGELOG-2026-04-16-smart-screenshots.md $DST/docs/changelog-original.md
cp $SRC/docs/superpowers/specs/2026-04-16-smart-screenshots-design.md $DST/docs/specs/2026-04-16-v1-design.md
cp $SRC/docs/superpowers/specs/2026-04-17-screenshot-v2-design.md $DST/docs/specs/2026-04-17-v2-design.md
cp $SRC/docs/superpowers/specs/2026-04-17-screenshot-v2-followups.md $DST/docs/specs/2026-04-17-v2-followups.md
cp $SRC/docs/superpowers/plans/2026-04-16-smart-screenshots.md $DST/docs/plans/2026-04-16-v1-implementation.md
cp $SRC/docs/superpowers/plans/2026-04-17-screenshot-v2.md $DST/docs/plans/2026-04-17-v2-implementation.md
```

- [ ] **Step 3: Verify all copies**

```bash
ls /mnt/d/labs/auto-screenshot/SKILL.md \
   /mnt/d/labs/auto-screenshot/capture.ps1 \
   /mnt/d/labs/auto-screenshot/tests \
   /mnt/d/labs/auto-screenshot/docs/changelog-original.md \
   /mnt/d/labs/auto-screenshot/docs/specs/2026-04-16-v1-design.md \
   /mnt/d/labs/auto-screenshot/docs/specs/2026-04-17-v2-design.md \
   /mnt/d/labs/auto-screenshot/docs/specs/2026-04-17-v2-followups.md \
   /mnt/d/labs/auto-screenshot/docs/plans/2026-04-16-v1-implementation.md \
   /mnt/d/labs/auto-screenshot/docs/plans/2026-04-17-v2-implementation.md
```
Expected: all paths exist.

---

### Task C3: Write `README.md` and `setup.md` for `auto-screenshot`

- [ ] **Step 1: Write `README.md`**

```markdown
# auto-screenshot

Window-aware screen capture skill for Claude Code on Windows hosts. Enumerate open windows, target by title/PID/HWND, crop to client area. Multi-monitor aware, handles minimized + GPU-accelerated windows.

Originally shipped 2026-04-16 as `smart-screenshots` inside `claude-code-optimizations`; extracted and renamed `auto-screenshot` as part of the modular reorg. v2 (raise-without-focus + capture-overlay confirmation + audit fixes) is in flight — see `docs/specs/2026-04-17-v2-design.md` and `docs/plans/2026-04-17-v2-implementation.md`.

**Requires:** Windows host with PowerShell 5+; WSL access to `powershell.exe` (if running from WSL); Pester v5 for tests.

See `setup.md` to install.
```

- [ ] **Step 2: Write `setup.md`** (adapting existing changelog deployment section)

````markdown
# auto-screenshot — setup

**Requires:** Windows host, PowerShell 5+, WSL access to `powershell.exe`; Pester v5 for tests (`Install-Module Pester -Force -SkipPublisherCheck -Scope CurrentUser`)

## Per-machine values

- `<REPO_PATH>` — absolute path to this repo's clone (used in the symlink target).

## Files

The skill is symlinked into `~/.claude/skills/screenshot/` so edits in this repo flow through immediately without copy steps.

## Install

```bash
# SAFETY: verify it's a real directory or symlink, not unrelated
if [ -L ~/.claude/skills/screenshot ]; then
    rm ~/.claude/skills/screenshot
elif [ -d ~/.claude/skills/screenshot ]; then
    mv ~/.claude/skills/screenshot ~/.claude/skills/screenshot.bak
fi
ln -s <REPO_PATH> ~/.claude/skills/screenshot
```

After this the skill is live; no further deploy step is needed when this repo is updated.

## Verify

See `docs/changelog-original.md` § "Verification" — 10 scenarios covering byte-identical legacy output, Pester suite, list-windows, window mode, region cropping, problematic apps, minimized windows, JSON format, window-crop, error paths.

Quick smoke:

```bash
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w ~/.claude/skills/screenshot/capture.ps1)" -Mode overview
```
Expected: `overview|<path>|1200x675|capture_id=<ID>`.

## Uninstall

```bash
rm ~/.claude/skills/screenshot  # the symlink
```
````

- [ ] **Step 3: Verify**

```bash
ls /mnt/d/labs/auto-screenshot/README.md /mnt/d/labs/auto-screenshot/setup.md
```
Expected: both listed.

---

### Task C4: Initial commit on `auto-screenshot`

- [ ] **Step 1: Stage all**

```bash
git -C /mnt/d/labs/auto-screenshot add -A
git -C /mnt/d/labs/auto-screenshot status --short
```

- [ ] **Step 2: Commit**

```bash
git -C /mnt/d/labs/auto-screenshot commit -m "$(cat <<'EOF'
init: auto-screenshot (extracted from claude-code-optimizations)

Window-aware screen capture skill for Claude Code on Windows. Originally shipped
as smart-screenshots inside claude-code-optimizations on 2026-04-16; renamed to
auto-screenshot and extracted into its own repo as part of the modular reorg.

The v2 spec (correctness, capture-overlay confirmation, 24 audit fixes) is in
flight — see docs/specs/2026-04-17-v2-design.md and docs/plans/2026-04-17-v2-implementation.md.
EOF
)"
```

- [ ] **Step 3: Set sync tag**

```bash
git -C /mnt/d/labs/auto-screenshot tag synced-on-$(hostname)
```

---

### Task C5: Re-symlink `~/.claude/skills/screenshot` → new repo

The current symlink (per the 2026-04-16 changelog) points at `claude-code-optimizations/config/skills/screenshot`. After Phase C the source moves to `auto-screenshot/`. Update the symlink so the live skill keeps working.

- [ ] **Step 1: Verify current symlink target**

Run: `ls -l ~/.claude/skills/screenshot`
Expected: symlink pointing at `claude-code-optimizations/config/skills/screenshot` (the old location).

- [ ] **Step 2: Remove old symlink**

Run: `rm ~/.claude/skills/screenshot`

- [ ] **Step 3: Create new symlink**

Run: `ln -s /mnt/d/labs/auto-screenshot ~/.claude/skills/screenshot`

- [ ] **Step 4: Verify new symlink and skill discovery**

```bash
ls -l ~/.claude/skills/screenshot
ls ~/.claude/skills/screenshot/SKILL.md
```
Expected: symlink resolves to `/mnt/d/labs/auto-screenshot`; SKILL.md path resolves.

---

### Task C6: Delete extracted sources from `claude-code-optimizations`

**Files:**
- Delete: `config/skills/screenshot/` (entire folder)
- Delete: `docs/superpowers/specs/2026-04-16-smart-screenshots-design.md`
- Delete: `docs/superpowers/specs/2026-04-17-screenshot-v2-design.md`
- Delete: `docs/superpowers/specs/2026-04-17-screenshot-v2-followups.md`
- Delete: `docs/superpowers/plans/2026-04-16-smart-screenshots.md`
- Delete: `docs/superpowers/plans/2026-04-17-screenshot-v2.md`

- [ ] **Step 1: Cut branch**

```bash
git -C /mnt/d/labs/claude-code-optimizations checkout -b reorg/extract-screenshot
```

- [ ] **Step 2: `git rm` each path**

```bash
cd /mnt/d/labs/claude-code-optimizations
git rm -r config/skills/screenshot/
git rm docs/superpowers/specs/2026-04-16-smart-screenshots-design.md \
       docs/superpowers/specs/2026-04-17-screenshot-v2-design.md \
       docs/superpowers/specs/2026-04-17-screenshot-v2-followups.md \
       docs/superpowers/plans/2026-04-16-smart-screenshots.md \
       docs/superpowers/plans/2026-04-17-screenshot-v2.md
```

- [ ] **Step 3: Verify gone**

```bash
ls /mnt/d/labs/claude-code-optimizations/config/skills/screenshot \
   /mnt/d/labs/claude-code-optimizations/docs/superpowers/specs/2026-04-16-smart-screenshots-design.md \
   /mnt/d/labs/claude-code-optimizations/docs/superpowers/specs/2026-04-17-screenshot-v2-design.md \
   /mnt/d/labs/claude-code-optimizations/docs/superpowers/specs/2026-04-17-screenshot-v2-followups.md \
   /mnt/d/labs/claude-code-optimizations/docs/superpowers/plans/2026-04-16-smart-screenshots.md \
   /mnt/d/labs/claude-code-optimizations/docs/superpowers/plans/2026-04-17-screenshot-v2.md 2>&1 | grep -c 'No such file'
```
Expected: `6`.

- [ ] **Step 4: Confirm `config/skills/` and `config/` are now empty (or near-empty)**

Run: `find /mnt/d/labs/claude-code-optimizations/config -type f 2>/dev/null`
Expected: empty output (everything inside `config/` has now migrated out — the folder itself gets deleted in Phase E).

- [ ] **Step 5: Commit and merge**

```bash
git -C /mnt/d/labs/claude-code-optimizations commit -m "reorg: extract auto-screenshot to /mnt/d/labs/auto-screenshot (renamed from smart-screenshots)"
git -C /mnt/d/labs/claude-code-optimizations checkout main
git -C /mnt/d/labs/claude-code-optimizations merge --no-ff reorg/extract-screenshot -m "reorg: Phase C — extract auto-screenshot"
git -C /mnt/d/labs/claude-code-optimizations tag -f synced-on-$(hostname)
```

---

## Phase D: Restructure `wezterm`

### Task D1: Survey wezterm changelogs and finalize module names

The spec defers final module names to migration time. Do this once, write the result down, then proceed.

- [ ] **Step 1: List existing changelogs**

```bash
ls /mnt/d/labs/wezterm/changelogs/
```
Expected: 12 files (per 2026-05-02 state).

- [ ] **Step 2: Decide module groupings**

Working list (consolidate the spec's working list with any judgement at migration time). Default unless overridden:

| Module name | Source changelog(s) |
|---|---|
| `tab-nav-keybindings` | `CHANGELOG-2026-03-30-tab-nav-keybinding-remap.md` |
| `vertical-scrollbar` | `CHANGELOG-2026-04-04-vertical-scrollbar.md` |
| `default-cwd` | `CHANGELOG-2026-04-10-default-cwd-wezterm.md` (subsumes the earlier `conditional-cd-bashrc` per the summary's "replaced by" note) |
| `tab-bar-style` | `CHANGELOG-2026-04-10-tab-bar-top-fancy-themed.md` + `CHANGELOG-2026-04-15-tab-bar-font-size-fix.md` (consolidate) |
| `ctrl-drag-window-move` | `CHANGELOG-2026-04-10-ctrl-drag-window-move.md` |
| `smart-cd` | `CHANGELOG-2026-04-14-smart-cd-fuzzy-picker.md` + `CHANGELOG-2026-04-15-smart-cd-configurable-root.md` (consolidate) |
| `pane-splitting` | `CHANGELOG-2026-04-14-pane-splitting-power-user.md` |
| `split-pane-cwd` | `CHANGELOG-2026-04-14-split-pane-inherit-cwd.md` + `CHANGELOG-2026-04-14-split-pane-cwd-robustness.md` (consolidate) |

That's 8 modules from 12 changelogs. The `conditional-cd-bashrc` is marked as replaced; its content becomes a footnote in `default-cwd/setup.md` for posterity.

- [ ] **Step 3: Cut migration branch**

```bash
git -C /mnt/d/labs/wezterm checkout -b reorg/modular-layout
```

---

### Task D2: For each module, create folder + README + setup.md

For each of the 8 modules above, do the following sub-steps. Pattern for ONE module (`tab-nav-keybindings`):

- [ ] **Step 1: Verify destination doesn't exist**

Run: `ls /mnt/d/labs/wezterm/tab-nav-keybindings 2>&1`
Expected: `No such file or directory`.

- [ ] **Step 2: Create folder**

Run: `mkdir -p /mnt/d/labs/wezterm/tab-nav-keybindings`

- [ ] **Step 3: Write `README.md`**

A 2-4 line summary of what the module does (read the source changelog, distill).

- [ ] **Step 4: Write `setup.md`**

Adapt the source changelog into install-instruction shape:
- `**Requires:**` line at top (typically `WezTerm` + any extras like `bash`, `fdfind` for smart-cd, etc.)
- `## Per-machine values` (e.g. `SMART_CD_ROOT` for smart-cd module — none for most)
- `## Files` table (source → destination, where most go into `C:\Users\<WIN_USER>\.wezterm.lua` as patches/snippets)
- `## Install` steps with the actual config-file edits or bash commands
- `## Verify` from the changelog's verification section

- [ ] **Step 5: Stage and commit this module**

```bash
git -C /mnt/d/labs/wezterm add tab-nav-keybindings/
git -C /mnt/d/labs/wezterm commit -m "reorg: create tab-nav-keybindings/ module"
```

**Repeat steps 1–5 for all 8 modules** (`vertical-scrollbar`, `default-cwd`, `tab-bar-style`, `ctrl-drag-window-move`, `smart-cd`, `pane-splitting`, `split-pane-cwd`). Modules consolidating multiple changelogs should mention both sources in their `setup.md` ("originally introduced in X, refined in Y").

---

### Task D3: Write top-level `setup.md`, `README.md`, slim `CLAUDE.md`

**Files:**
- Create: `wezterm/setup.md` (orchestration)
- Create: `wezterm/README.md` (or rewrite if exists)
- Modify: `wezterm/CLAUDE.md` (slim to new layout language; mirror `claude-code-optimizations/CLAUDE.md`)
- (`wezterm/AGENTS.md` is currently a deleted-mirror of `CLAUDE.md` per `git status` — will be re-aligned in Step 4)

- [ ] **Step 1: Write top-level `setup.md`** (orchestration menu, modeled on Phase A's Task A5; module table lists the 8 wezterm modules + a "See also" section for cross-cutting `claude-waiting-notification` and `spawn-session`)

- [ ] **Step 2: Rewrite `wezterm/README.md`** (modeled on Phase A's Task A6)

- [ ] **Step 3: Slim `wezterm/CLAUDE.md`** to use the new language (module-folder layout + sync model). Use `claude-code-optimizations/CLAUDE.md` as the template, swap "WezTerm config" for the role-specific text.

- [ ] **Step 4: Re-mirror `AGENTS.md` from the new `CLAUDE.md`**

```bash
cp /mnt/d/labs/wezterm/CLAUDE.md /mnt/d/labs/wezterm/AGENTS.md
git -C /mnt/d/labs/wezterm add CLAUDE.md AGENTS.md README.md setup.md
```

- [ ] **Step 5: Commit**

```bash
git -C /mnt/d/labs/wezterm commit -m "reorg: top-level setup.md / README / CLAUDE.md / AGENTS.md for module layout"
```

---

### Task D4: Delete event-sourcing meta from `wezterm`

**Files:**
- Delete: `CHANGELOG-SUMMARY.md`
- Delete: `SETUP-GUIDE.md`
- Delete: `changelogs/` (entire folder — sources are already in the per-module `setup.md`s by this point)

- [ ] **Step 1: `git rm`**

```bash
cd /mnt/d/labs/wezterm
git rm CHANGELOG-SUMMARY.md SETUP-GUIDE.md
git rm -r changelogs/
```

- [ ] **Step 2: Verify gone**

```bash
ls /mnt/d/labs/wezterm/CHANGELOG-SUMMARY.md /mnt/d/labs/wezterm/SETUP-GUIDE.md /mnt/d/labs/wezterm/changelogs 2>&1 | grep -c 'No such file'
```
Expected: `3`.

- [ ] **Step 3: Commit and merge**

```bash
git -C /mnt/d/labs/wezterm commit -m "reorg: drop event-sourcing meta (CHANGELOG-SUMMARY, SETUP-GUIDE, changelogs/)"
git -C /mnt/d/labs/wezterm checkout main
git -C /mnt/d/labs/wezterm merge --no-ff reorg/modular-layout -m "reorg: Phase D — module-folder layout for wezterm"
git -C /mnt/d/labs/wezterm tag -f synced-on-$(hostname)
```

---

## Phase E: Final cleanup commit on `claude-code-optimizations`

### Task E1: Delete `changelogs/`, `docs/superpowers/`, empty `config/`

**Files:**
- Delete: `changelogs/` (entire folder — its two cross-cutting changelogs were copied into Phase B and C repos respectively)
- Delete: `docs/superpowers/` (specs and plans both — only this plan and the modular-reorg spec remain by this point; both committed historically, retrievable via git log)
- Delete: `config/` (now-empty directory)

- [ ] **Step 1: Cut branch**

```bash
git -C /mnt/d/labs/claude-code-optimizations checkout -b reorg/final-cleanup
```

- [ ] **Step 2: Verify `docs/superpowers/specs/` contains only the modular-reorg spec, and `docs/superpowers/plans/` only this plan**

```bash
ls /mnt/d/labs/claude-code-optimizations/docs/superpowers/specs/
ls /mnt/d/labs/claude-code-optimizations/docs/superpowers/plans/
```
Expected: each directory contains exactly one file (`2026-05-02-modular-reorg-design.md` and `2026-05-02-modular-reorg.md` respectively).

- [ ] **Step 3: Verify `config/` is empty**

Run: `find /mnt/d/labs/claude-code-optimizations/config -type f 2>/dev/null | wc -l`
Expected: `0`.

- [ ] **Step 4: `git rm` everything**

```bash
cd /mnt/d/labs/claude-code-optimizations
git rm -r changelogs/ docs/superpowers/ config/
```

(`config/` may be empty-but-tracked or already gone if all files were removed via `git rm` earlier; the `-r` handles either case.)

- [ ] **Step 5: Verify gone**

```bash
ls /mnt/d/labs/claude-code-optimizations/changelogs \
   /mnt/d/labs/claude-code-optimizations/docs/superpowers \
   /mnt/d/labs/claude-code-optimizations/config 2>&1 | grep -c 'No such file'
```
Expected: `3`.

- [ ] **Step 6: Commit and merge**

```bash
git -C /mnt/d/labs/claude-code-optimizations commit -m "reorg: Phase E — drop changelogs/, docs/superpowers/, empty config/"
git -C /mnt/d/labs/claude-code-optimizations checkout main
git -C /mnt/d/labs/claude-code-optimizations merge --no-ff reorg/final-cleanup -m "reorg: Phase E — final cleanup (drop changelogs/, docs/superpowers/, config/)"
git -C /mnt/d/labs/claude-code-optimizations tag -f synced-on-$(hostname)
```

---

### Task E2: End-state verification on both baselines

- [ ] **Step 1: `claude-code-optimizations` final layout**

```bash
ls /mnt/d/labs/claude-code-optimizations/
```
Expected, exactly: `.changelog-status` (or absent — git-ignored, leftover ok), `.claude/`, `.git/`, `.gitignore`, `CLAUDE.md`, `README.md`, `baseline-settings/`, `claude-md/`, `setup.md`, `statusline/`. No `config/`, no `changelogs/`, no `docs/`, no `CHANGELOG-SUMMARY.md`, no `SETUP-GUIDE.md`, no `AUDIT-PROMPT-notification-system.md`.

- [ ] **Step 2: `wezterm` final layout**

```bash
ls /mnt/d/labs/wezterm/
```
Expected, exactly: `.changelog-status` (or absent), `.claude/`, `.git/`, `.gitignore`, `AGENTS.md`, `CLAUDE.md`, `README.md`, 8 module folders, `setup.md`. No `changelogs/`, no `CHANGELOG-SUMMARY.md`, no `SETUP-GUIDE.md`.

- [ ] **Step 3: Cross-cutting repos all exist**

```bash
ls -d /mnt/d/labs/claude-waiting-notification /mnt/d/labs/auto-screenshot /mnt/d/labs/spawn-session
```
Expected: all three.

- [ ] **Step 4: Sync tags exist on every repo**

```bash
for repo in claude-code-optimizations wezterm claude-waiting-notification auto-screenshot; do
  echo "=== $repo ==="
  git -C /mnt/d/labs/$repo tag --list "synced-on-*"
done
```
Expected: each repo lists its `synced-on-<hostname>` tag.

- [ ] **Step 5: `~/.claude/skills/screenshot` symlink resolves to new repo**

```bash
readlink ~/.claude/skills/screenshot
```
Expected: `/mnt/d/labs/auto-screenshot`.

- [ ] **Step 6: Delete stale `.changelog-status` files**

The `.changelog-status` files become meaningless under the new sync model.

```bash
rm -f /mnt/d/labs/claude-code-optimizations/.changelog-status
rm -f /mnt/d/labs/wezterm/.changelog-status
```

(These are git-ignored; no commit needed.)

---

## Phase F: GitHub push + URL update

### Task F1: Create GitHub repos and push

This step requires the user. The agent should not push to GitHub or create remote repos without explicit approval.

- [ ] **Step 1: Confirm with the user**

Tell the user:
> "Phase E is done — local layouts are final. Phase F creates GitHub repos for `claude-waiting-notification` and `auto-screenshot` (the two new ones), pushes their initial commits, and updates the placeholder URLs. Want me to walk through the GitHub steps, or do you want to handle the push yourself and just have me update the URLs after?"

Wait for user direction.

- [ ] **Step 2: Push (if approved)**

After the user has created the GitHub repos (or authorized the agent to via `gh repo create`):

```bash
# Replace <GH_USER> with the user's GitHub username
git -C /mnt/d/labs/claude-waiting-notification remote add origin git@github.com:<GH_USER>/claude-waiting-notification.git
git -C /mnt/d/labs/claude-waiting-notification push -u origin main

git -C /mnt/d/labs/auto-screenshot remote add origin git@github.com:<GH_USER>/auto-screenshot.git
git -C /mnt/d/labs/auto-screenshot push -u origin main
```

- [ ] **Step 3: Verify pushes**

```bash
git -C /mnt/d/labs/claude-waiting-notification ls-remote origin
git -C /mnt/d/labs/auto-screenshot ls-remote origin
```
Expected: each shows the `main` ref at the local commit hash.

---

### Task F2: Replace placeholder URLs in baseline `setup.md`s

**Files:**
- Modify: `claude-code-optimizations/setup.md` (replace 3 `<TBD: github URL once published>` placeholders)
- Modify: `wezterm/setup.md` (replace ≤2 placeholders — only the cross-cutting ones relevant to wezterm)

- [ ] **Step 1: Find every placeholder**

```bash
grep -rn '<TBD: github URL once published>' /mnt/d/labs/claude-code-optimizations/ /mnt/d/labs/wezterm/ 2>/dev/null
```
Expected: up to 5 hits (3 in `claude-code-optimizations/setup.md`, 2 in `wezterm/setup.md`). If `spawn-session` is not yet published to GitHub, two of those will remain as placeholders after this phase — that's fine; resolve them whenever spawn-session lands.

- [ ] **Step 2: Replace using `sed`**

```bash
GH=<GH_USER>  # set to the user's GitHub handle

sed -i "s|<TBD: github URL once published>|https://github.com/$GH/claude-waiting-notification|" /mnt/d/labs/claude-code-optimizations/setup.md  # replaces the first occurrence per run; repeat or use targeted replacements
```

Better to do per-line targeted replacements via the agent's Edit tool with each module name to avoid wrong-target replacements. Three substitutions in `claude-code-optimizations/setup.md`:
- "claude-waiting-notification" line → `https://github.com/<GH>/claude-waiting-notification`
- "auto-screenshot" line → `https://github.com/<GH>/auto-screenshot`
- "spawn-session" line → `https://github.com/<GH>/spawn-session` (assuming spawn-session is on GitHub by now; if not, leave the placeholder)

Two in `wezterm/setup.md`:
- "claude-waiting-notification" line
- "spawn-session" line

- [ ] **Step 3: Verify no placeholders remain (except intentional ones)**

```bash
grep -rn '<TBD: github URL once published>' /mnt/d/labs/claude-code-optimizations/ /mnt/d/labs/wezterm/ 2>/dev/null
```
Expected: empty output (or only intentional remaining ones for repos not yet pushed).

- [ ] **Step 4: Commit on each baseline**

```bash
git -C /mnt/d/labs/claude-code-optimizations add setup.md
git -C /mnt/d/labs/claude-code-optimizations commit -m "reorg: fill in GitHub URLs for cross-cutting tools"
git -C /mnt/d/labs/claude-code-optimizations tag -f synced-on-$(hostname)

git -C /mnt/d/labs/wezterm add setup.md
git -C /mnt/d/labs/wezterm commit -m "reorg: fill in GitHub URLs for cross-cutting tools"
git -C /mnt/d/labs/wezterm tag -f synced-on-$(hostname)
```

- [ ] **Step 5: Push baselines**

```bash
git -C /mnt/d/labs/claude-code-optimizations push
git -C /mnt/d/labs/wezterm push
```

(Assumes both already have a GitHub remote configured. If not, add via `gh repo create` or manual `remote add` first.)

---

## Notes for the executor

- **No worktree.** Migration cuts across multiple repos; a worktree on one repo would only cover Phase A. Run on the working clones.
- **Branch convention.** Each phase that modifies an existing repo uses its own `reorg/<phase>` branch, merged with `--no-ff` to make phase boundaries visible in `git log`.
- **Cross-repo file moves use copy + git rm**, not `git mv` (which doesn't work cross-repo). Git history attribution is preserved at the source-repo side; the destination-repo side starts a fresh history for the file. That's fine — the `docs/specs/` and `docs/changelog-original.md` in each new repo carry forward the design history as documentation.
- **Sync tag (`synced-on-<hostname>`)** is set after every merge to main and after Phase F's URL commit. This way subsequent machine syncs use the right baseline.
- **Symlink update in Phase C Task C5 is on the live machine.** If executing this plan on a different machine than the one originally hosting the symlink, that machine's symlink may not exist yet; install via `auto-screenshot/setup.md` instead of the rewrite step.
- **Other machines (e.g. work PC) sync separately.** They will see Phase A through E land in `claude-code-optimizations` and Phase D land in `wezterm` on next `git pull`. They'll also need to clone `claude-waiting-notification` and `auto-screenshot` separately — the new `setup.md` "See also" sections give the URLs, the sync flow surfaces the new dependency.

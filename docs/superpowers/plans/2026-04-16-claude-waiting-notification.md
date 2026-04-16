# Claude Waiting Notification System — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When Claude Code goes idle, play a Windows chime, highlight the WezTerm tab amber, and (if WezTerm is in the background) bring it to front and switch to the waiting tab.

**Architecture:** A `Stop` hook script handles sound + pane marking + conditional focus raise via PowerShell Win32 calls. A `UserPromptSubmit` hook script clears the marker. WezTerm's `format-tab-title` Lua event reads the marker and renders waiting tabs in amber. No daemons, no polling.

**Tech Stack:** Bash, PowerShell (called from WSL), WezTerm Lua config, Claude Code hooks (`settings.json`)

---

## File Map

| File | Status | Purpose |
|---|---|---|
| `~/.claude/hooks/notify-waiting.sh` | Create | Stop hook: play sound, mark pane, conditionally raise WezTerm |
| `~/.claude/hooks/clear-waiting.sh` | Create | UserPromptSubmit hook: clear CLAUDE_WAITING user var |
| `~/.config/wezterm/wezterm.lua` | Create (does not exist) | WezTerm Lua config: amber tab highlight via format-tab-title |
| `~/.claude/settings.json` | Modify | Add notify + clear scripts to Stop and UserPromptSubmit hooks |
| `config/hooks/notify-waiting.sh` | Create | Repo copy with `<-- edit per machine` path markers |
| `config/hooks/clear-waiting.sh` | Create | Repo copy |
| `config/settings.json` | Modify | Mirror live settings.json hook changes |

---

## Task 1: Create `notify-waiting.sh`

**Files:**
- Create: `~/.claude/hooks/notify-waiting.sh`

- [ ] **Step 1: Create the script**

```bash
#!/usr/bin/env bash
# Claude Code Stop hook — notify user that Claude is waiting for input
#
# Behavior:
#   1. Play Windows chime (always, even outside WezTerm)
#   2. If WEZTERM_PANE is unset, exit (not in WezTerm)
#   3. Mark the pane with CLAUDE_WAITING=1 user var
#   4. If WezTerm is already foreground, exit (highlight is enough)
#   5. Switch to the waiting tab and raise WezTerm window

set -euo pipefail

# Step 1: Sound (synchronous ~1s, runs async so doesn't block Claude)
powershell.exe -NoProfile -WindowStyle Hidden -Command \
  "[System.Media.SystemSounds]::Asterisk.Play()"

# Step 2: Guard — only proceed if running inside WezTerm
[ -z "${WEZTERM_PANE:-}" ] && exit 0

# Step 3: Mark the pane as waiting
wezterm cli set-user-var --pane-id "$WEZTERM_PANE" CLAUDE_WAITING 1

# Step 4: Check if WezTerm is already the foreground window
FOREGROUND_PROC=$(powershell.exe -NoProfile -WindowStyle Hidden -Command "
  Add-Type -Name Win32 -Namespace '' -MemberDefinition '
    [DllImport(\"user32.dll\")] public static extern IntPtr GetForegroundWindow();
    [DllImport(\"user32.dll\")] public static extern int GetWindowThreadProcessId(IntPtr hWnd, out int lpdwProcessId);
  '
  \$hwnd = [Win32]::GetForegroundWindow()
  \$pid = 0
  [Win32]::GetWindowThreadProcessId(\$hwnd, [ref]\$pid) | Out-Null
  (Get-Process -Id \$pid -ErrorAction SilentlyContinue).ProcessName
" 2>/dev/null | tr -d '\r')

# wezterm-gui (typical install) or wezterm (some installs)
case "${FOREGROUND_PROC:-}" in
  wezterm*) exit 0 ;;
esac

# Step 5: Switch to the waiting pane, then raise WezTerm window
wezterm cli activate-pane --pane-id "$WEZTERM_PANE"

powershell.exe -NoProfile -WindowStyle Hidden -Command "
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport(\"user32.dll\")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport(\"user32.dll\")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@
  \$proc = Get-Process -Name 'wezterm-gui','wezterm' -ErrorAction SilentlyContinue |
             Where-Object { \$_.MainWindowHandle -ne 0 } |
             Select-Object -First 1
  if (\$proc) {
    [Win32]::ShowWindow(\$proc.MainWindowHandle, 9)   # SW_RESTORE
    [Win32]::SetForegroundWindow(\$proc.MainWindowHandle)
  }
"
```

Write to `~/.claude/hooks/notify-waiting.sh`.

- [ ] **Step 2: Make it executable**

```bash
chmod +x ~/.claude/hooks/notify-waiting.sh
```

- [ ] **Step 3: Smoke-test the script in isolation**

Run it directly from a WezTerm pane:
```bash
~/.claude/hooks/notify-waiting.sh
```

Expected: you hear a Windows chime. The tab you're on does NOT turn amber yet (wezterm.lua isn't wired yet). No errors printed.

- [ ] **Step 4: Test the non-WezTerm guard**

```bash
env -u WEZTERM_PANE ~/.claude/hooks/notify-waiting.sh
```

Expected: chime plays, script exits silently at step 2, no `wezterm cli` errors.

- [ ] **Step 5: Commit**

```bash
git -C ~/.claude add hooks/notify-waiting.sh
git -C ~/.claude commit -m "feat: add notify-waiting.sh Stop hook"
```

---

## Task 2: Create `clear-waiting.sh`

**Files:**
- Create: `~/.claude/hooks/clear-waiting.sh`

- [ ] **Step 1: Create the script**

```bash
#!/usr/bin/env bash
# Claude Code UserPromptSubmit hook — clear CLAUDE_WAITING when user replies

[ -z "${WEZTERM_PANE:-}" ] && exit 0
wezterm cli set-user-var --pane-id "$WEZTERM_PANE" CLAUDE_WAITING 0
```

Write to `~/.claude/hooks/clear-waiting.sh`.

- [ ] **Step 2: Make it executable**

```bash
chmod +x ~/.claude/hooks/clear-waiting.sh
```

- [ ] **Step 3: Smoke-test**

```bash
~/.claude/hooks/clear-waiting.sh
```

Expected: runs silently, no errors. (Sets CLAUDE_WAITING=0 on current pane — harmless at this stage.)

- [ ] **Step 4: Commit**

```bash
git -C ~/.claude add hooks/clear-waiting.sh
git -C ~/.claude commit -m "feat: add clear-waiting.sh UserPromptSubmit hook"
```

---

## Task 3: Create `wezterm.lua`

**Files:**
- Create: `~/.config/wezterm/wezterm.lua`

This file does not exist yet. We create it with only the notification handler — no other WezTerm customisation. If the user later adds more WezTerm config, they add it to this file.

**Important:** If `~/.config/wezterm/wezterm.lua` already exists by the time you execute this task, do NOT overwrite it. Instead, merge the `format-tab-title` handler into the existing file.

- [ ] **Step 1: Verify the file truly does not exist**

```bash
ls ~/.config/wezterm/wezterm.lua 2>&1
```

Expected: `ls: cannot access ...` (file not found). If it exists, read it first and merge in step 2 instead.

- [ ] **Step 2: Create `~/.config/wezterm/wezterm.lua`**

```lua
local wezterm = require 'wezterm'

-- Claude Code waiting notification: highlight tab amber when CLAUDE_WAITING=1
--
-- Set by: ~/.claude/hooks/notify-waiting.sh  (Stop hook)
-- Cleared by: ~/.claude/hooks/clear-waiting.sh  (UserPromptSubmit hook)
--
-- IMPORTANT: WezTerm only calls one format-tab-title handler.
-- If you add other tab title customisation later, merge it into this function
-- rather than registering a second wezterm.on('format-tab-title', ...) call.
wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
  -- `panes` is already scoped to this tab — iterate directly
  for _, pane in ipairs(panes) do
    if pane.user_vars.CLAUDE_WAITING == '1' then
      return {
        { Background = { Color = '#e0af68' } },  -- Tokyo Night amber
        { Foreground = { Color = '#1a1b26' } },  -- dark text for contrast
        { Text = ' ' .. tab.active_pane.title .. ' ' },
      }
    end
  end
  -- Return nothing to use WezTerm's default tab rendering
end)

return wezterm.config_builder and wezterm.config_builder() or {}
```

- [ ] **Step 3: Verify WezTerm picks up the config**

Open a new WezTerm tab (or restart WezTerm). If `~/.config/wezterm/wezterm.lua` has a syntax error, WezTerm shows an error overlay on startup.

Expected: WezTerm opens normally, no error overlay.

- [ ] **Step 4: Manually test the amber highlight**

From any WezTerm pane, run:
```bash
wezterm cli set-user-var --pane-id "$WEZTERM_PANE" CLAUDE_WAITING 1
```

Expected: the tab for your current pane turns amber immediately.

Then clear it:
```bash
wezterm cli set-user-var --pane-id "$WEZTERM_PANE" CLAUDE_WAITING 0
```

Expected: tab returns to normal color.

- [ ] **Step 5: Commit**

```bash
git -C ~/.config/wezterm add wezterm.lua
git -C ~/.config/wezterm commit -m "feat: amber tab highlight when Claude is waiting"
```

If `~/.config/wezterm` is not a git repo, skip the commit and note this file for manual backup.

---

## Task 4: Wire hooks into `~/.claude/settings.json`

**Files:**
- Modify: `~/.claude/settings.json`

The live settings.json currently has `Stop` and `UserPromptSubmit` hooks that each contain a single `agent-deck hook-handler` entry. We add our new scripts alongside them.

- [ ] **Step 1: Read the current Stop hook block**

Read `~/.claude/settings.json` lines 125–135 (the `Stop` block) to confirm current structure matches:
```json
"Stop": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "agent-deck hook-handler",
        "async": true
      }
    ]
  }
]
```

- [ ] **Step 2: Update the Stop hooks array**

Replace the `Stop` block with:
```json
"Stop": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "agent-deck hook-handler",
        "async": true
      },
      {
        "type": "command",
        "command": "bash /home/pudge/.claude/hooks/notify-waiting.sh",
        "async": true
      }
    ]
  }
]
```

- [ ] **Step 3: Update the UserPromptSubmit hooks array**

Replace the `UserPromptSubmit` block with:
```json
"UserPromptSubmit": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "agent-deck hook-handler",
        "async": true
      },
      {
        "type": "command",
        "command": "bash /home/pudge/.claude/hooks/clear-waiting.sh"
      }
    ]
  }
]
```

Note: `clear-waiting.sh` has no `"async": true` — it runs synchronously so the pane var is cleared before Claude starts processing the new prompt.

- [ ] **Step 4: Validate the JSON is well-formed**

```bash
python3 -c "import json; json.load(open('/home/pudge/.claude/settings.json')); print('OK')"
```

Expected output: `OK`

If you get a parse error, read the file and fix the syntax before proceeding.

- [ ] **Step 5: End-to-end test**

Start or switch to an existing Claude Code session. Wait for Claude to finish a response (or trigger one). Watch the WezTerm tab.

Expected:
- You hear the chime
- The tab turns amber
- Typing a new prompt and submitting clears the amber

- [ ] **Step 6: Commit**

```bash
git -C ~/.claude add settings.json
git -C ~/.claude commit -m "feat: wire notify-waiting and clear-waiting hooks"
```

---

## Task 5: Add repo copies and update `config/settings.json`

**Files:**
- Create: `config/hooks/notify-waiting.sh`
- Create: `config/hooks/clear-waiting.sh`
- Modify: `config/settings.json`

These are the checked-in reference copies. The hook scripts get `<-- edit per machine` path markers per the repo convention.

- [ ] **Step 1: Copy `notify-waiting.sh` to repo with path marker**

Copy `~/.claude/hooks/notify-waiting.sh` to `config/hooks/notify-waiting.sh`, then add a comment on the line with the hardcoded WSL username:

The line:
```bash
        "command": "bash /home/pudge/.claude/hooks/notify-waiting.sh",
```
...appears in `settings.json`, not the script itself. The script has no hardcoded paths. So copy it as-is, adding a header comment:

```bash
#!/usr/bin/env bash
# Claude Code Stop hook — notify user that Claude is waiting for input
# Repo copy. No machine-specific values in this file.
# See config/settings.json for the path that references this script (<-- edit per machine).
```

Write `config/hooks/notify-waiting.sh` with the full script content (same as the live file, with the header comment added).

- [ ] **Step 2: Copy `clear-waiting.sh` to repo**

Write `config/hooks/clear-waiting.sh` with the full script content and similar header comment.

- [ ] **Step 3: Update `config/settings.json` Stop hook**

`config/settings.json` currently has the same `Stop` block as the live file (single `agent-deck` entry). Apply the same change as Task 4 Step 2, but with a path marker:

```json
{
  "type": "command",
  "command": "bash /home/pudge/.claude/hooks/notify-waiting.sh", // <-- edit per machine: WSL username (pudge)
  "async": true
}
```

- [ ] **Step 4: Update `config/settings.json` UserPromptSubmit hook**

Apply the same change as Task 4 Step 3, with path marker:

```json
{
  "type": "command",
  "command": "bash /home/pudge/.claude/hooks/clear-waiting.sh" // <-- edit per machine: WSL username (pudge)
}
```

- [ ] **Step 5: Validate `config/settings.json` is well-formed**

Note: `config/settings.json` uses `//` comments (JSON5-style), which standard `json` parsers reject. Skip Python validation here — visual inspection is sufficient. Confirm the braces and brackets are balanced.

- [ ] **Step 6: Commit everything to the optimizations repo**

```bash
git -C /mnt/d/labs/claude-code-optimizations add \
  config/hooks/notify-waiting.sh \
  config/hooks/clear-waiting.sh \
  config/settings.json
git -C /mnt/d/labs/claude-code-optimizations commit -m \
  "feat: add claude-waiting notification hooks and wezterm tab highlight"
```

---

## Task 6: Add changelog entry

**Files:**
- Create: `changelogs/CHANGELOG-2026-04-16-claude-waiting-notification.md`
- Modify: `CHANGELOG-SUMMARY.md`
- Modify: `.changelog-status`

- [ ] **Step 1: Create the changelog file**

```markdown
# CHANGELOG-2026-04-16-claude-waiting-notification

**Date:** 2026-04-16
**Tag:** [core]
**Summary:** Ambient notification system — chime + amber WezTerm tab when Claude goes idle.

## Goal

When Claude Code finishes responding, the user needs a non-intrusive signal:
- A Windows chime so they know it's done when they're in the browser
- An amber WezTerm tab so they can see which session needs attention when multiple are open
- Auto-focus raise when WezTerm is in the background (switches to the waiting tab)
- Tab clears to normal when they submit the next prompt

## Change

**New files:**
- `config/hooks/notify-waiting.sh` — Stop hook: plays chime, sets CLAUDE_WAITING=1, conditionally raises WezTerm
- `config/hooks/clear-waiting.sh` — UserPromptSubmit hook: clears CLAUDE_WAITING=0

**Modified:**
- `config/settings.json` — Added both scripts to `Stop` (async) and `UserPromptSubmit` (sync) hooks

**Also requires (machine-side, not in repo):**
- `~/.config/wezterm/wezterm.lua` — `format-tab-title` handler that renders amber tabs when CLAUDE_WAITING=1

## Deployment

1. Copy `config/hooks/notify-waiting.sh` → `~/.claude/hooks/notify-waiting.sh` (substitute WSL username)
2. Copy `config/hooks/clear-waiting.sh` → `~/.claude/hooks/clear-waiting.sh`
3. `chmod +x` both scripts
4. Merge Stop and UserPromptSubmit hook entries into `~/.claude/settings.json`
5. Add the `format-tab-title` handler to `~/.config/wezterm/wezterm.lua` (create if absent)
   - See spec: `docs/superpowers/specs/2026-04-15-claude-waiting-notification-design.md` for the Lua snippet
   - IMPORTANT: WezTerm only calls one `format-tab-title` handler — merge into existing handler if present

## Verification

1. Start a Claude Code session
2. Ask Claude something, then switch to browser while it responds
3. Expected: hear chime, WezTerm comes to front, tab switches to waiting session, tab is amber
4. Submit a new prompt
5. Expected: amber clears
```

Write to `changelogs/CHANGELOG-2026-04-16-claude-waiting-notification.md`.

- [ ] **Step 2: Add to `CHANGELOG-SUMMARY.md`**

Append this line to the bottom of `CHANGELOG-SUMMARY.md`:

```
- [CHANGELOG-2026-04-16-claude-waiting-notification](changelogs/CHANGELOG-2026-04-16-claude-waiting-notification.md) — [core] Ambient notification: chime + amber WezTerm tab when Claude goes idle
```

- [ ] **Step 3: Mark as reviewed in `.changelog-status`**

Append to `.changelog-status`:
```
CHANGELOG-2026-04-16-claude-waiting-notification.md
```

- [ ] **Step 4: Commit**

```bash
git -C /mnt/d/labs/claude-code-optimizations add \
  changelogs/CHANGELOG-2026-04-16-claude-waiting-notification.md \
  CHANGELOG-SUMMARY.md \
  .changelog-status
git -C /mnt/d/labs/claude-code-optimizations commit -m \
  "docs: changelog for claude-waiting notification system"
```

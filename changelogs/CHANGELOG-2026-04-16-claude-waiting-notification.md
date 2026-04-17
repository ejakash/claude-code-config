# CHANGELOG-2026-04-16-claude-waiting-notification

**Date:** 2026-04-16
**Tag:** [core]
**Summary:** WezTerm-native notification system — tab amber, pane bg tint, Windows toast (with real Claude icon), auto-tab-switch + window raise when backgrounded, smart suppression when user is already on the waiting pane.

## Goal

When a Claude Code session goes idle, surface it with minimum friction:

- **Tab amber** on any tab that contains a waiting pane.
- **Pane bg tint** on the specific waiting pane (so the right pane is visible inside a multi-pane tab).
- **Windows toast** with the real Claude Desktop icon (via AUMID spoofing).
- **Auto-switch** to the waiting tab and **raise WezTerm** when user is in a different window.
- **No alert at all** when user is already on the waiting pane in a focused WezTerm.
- **Cleared** by: submitting input, clicking the pane, keyboard-activating the pane, Alt+N jump.

## Architecture

Three moving parts — one signal (OSC 1337 user var), centralised decision in Lua, thin helpers on both sides.

```
Stop hook (bash)        notify-waiting.sh       writes CLAUDE_WAITING=1
                                ↓
WezTerm Lua             user-var-changed        decides: suppress or alert
                        ├─ tint bg (OSC 11)     all alert side-effects
                        ├─ activate tab
                        ├─ window:focus()
                        └─ spawn toast PS1      .wezterm-claude-notify.ps1

Clear triggers:         UserPromptSubmit hook   clear-waiting.sh → CLAUDE_WAITING=0
                        mouse Up Left binding   (click in pane)
                        update-status handler   (active-pane change)
                        user-var-changed 0      resets bg tint (single source)
```

## Files

**Linux side (`~/.claude/hooks/`):**

- `notify-waiting.sh <1|0>` — single script used by both hooks. Walks the process tree to find the pane's pty and writes `\e]1337;SetUserVar=CLAUDE_WAITING=<base64>\a`. Stop hook calls it with `1`, UserPromptSubmit with `0`. No-op inside tmux (process-tree pty routing is unreliable there). Bg reset is handled by Lua's `user-var-changed` on value=0.

**Windows side (`C:\Users\<WIN_USER>\`):**

- `.wezterm-claude-notify.ps1` — pure toast. Uses Claude Desktop's AUMID so the toast shows the real Claude icon and branding. No chime (toast plays its own default sound), no window raise (done by WezTerm Lua).
- `.wezterm-claude-waiting.lua` — the feature's Lua module (loaded via `dofile` from the host `.wezterm.lua`). Owns the event handlers, keybindings, and mouse binding.
- `.wezterm.lua` — minimally modified: one `dofile` line, one `apply()` call, and one call to `format_tab_title_overlay` inside the existing `format-tab-title` handler. **WezTerm is a Windows app; it reads from `C:\Users\<WIN_USER>\.wezterm.lua`, NOT `~/.config/wezterm/` under WSL.**

**Claude Code settings (`~/.claude/settings.json`):**

```json
{
  "hooks": {
    "Stop": [{
      "hooks": [{ "type": "command", "command": "bash /home/<WSL_USER>/.claude/hooks/notify-waiting.sh 1", "async": true }]
    }],
    "UserPromptSubmit": [{
      "hooks": [{ "type": "command", "command": "bash /home/<WSL_USER>/.claude/hooks/notify-waiting.sh 0" }]
    }]
  }
}
```

Merge alongside any existing entries (e.g., `agent-deck hook-handler`).

## wezterm.lua — how to wire in

All event handlers, keybindings, and mouse bindings live in the standalone module `config/windows-helpers/claude-waiting.lua`. Host `.wezterm.lua` only needs three touch-points:

**1. Load and apply the module** (after `config = wezterm.config_builder()`):

```lua
local claude_waiting = dofile("C:\\Users\\<WIN_USER>\\.wezterm-claude-waiting.lua")
claude_waiting.apply(config, wezterm)
```

`apply()` registers `user-var-changed` and `update-status` handlers and appends the Alt+N keybind and left-click mouse binding to `config.keys` / `config.mouse_bindings`.

**2. Tab amber** — merge one call into the existing `format-tab-title` handler (WezTerm only fires the last-registered one, so this must be an in-place merge, not a separate registration):

```lua
wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
  local label = ...  -- your existing label computation

  local overlay = claude_waiting.format_tab_title_overlay(wezterm, tab, label)
  if overlay then return overlay end

  -- your existing default return
end)
```

`format_tab_title_overlay` returns a styled-text array (amber bg, dark fg) if any pane in the tab has `CLAUDE_WAITING=1`, or `nil` to let your default formatting run.

**3. Edit the toast-script path** inside `claude-waiting.lua`:

```lua
M.toast_script = "C:\\Users\\<WIN_USER>\\.wezterm-claude-notify.ps1"  -- <-- edit per machine
```

That's the full integration surface. The 140-line module does everything else.

## Machine-specific values

- `<WSL_USER>` — in hook paths in `~/.claude/settings.json`
- `<WIN_USER>` — in `CLAUDE_TOAST_SCRIPT` Lua constant and the copy destination for `.wezterm-claude-notify.ps1`
- **Claude Desktop AUMID** — the `Claude_pzs8sxrjxfjjc!Claude` literal in the PS1 is per-install. Find this machine's value with: `powershell.exe Get-StartApps | Where-Object Name -like '*Claude*'`.

## Key implementation notes

- **OSC 1337 SetUserVar** is the signal. `MQ==` = base64("1"), `MA==` = base64("0"). The CLI command `wezterm.exe cli set-user-var` does not exist — write the OSC directly to the pane's pty.
- **TTY discovery**: hooks run as Claude Code subprocesses with redirected fds. Walk `/proc/PID/fd/` until a `/dev/pts/*` symlink appears; keep walking up via PPid if not found.
- **WezTerm pane user vars are live**: `pane:get_user_vars()` on a `MuxTab:panes()` result returns current values. Do NOT use `tab.active_pane.user_vars` — that snapshot is stale.
- **Multiple `format-tab-title` handlers**: WezTerm only fires the last one registered. Merge logic into the existing handler if the user already has one.
- **Window raise**: `window:focus()` from Lua is a no-op when WezTerm is not the foreground app (at least on this WezTerm build). The PS1 uses the standard Windows workaround — a fake Alt keypress via `keybd_event` before `SetForegroundWindow` — to bypass focus-stealing protection.
- **Toast icon spoof**: on Windows, `CreateToastNotifier(AUMID)` shows the toast under that app's identity, including its icon. The AUMID for Claude Desktop comes from `Get-StartApps`.
- **Preempt `last_active_pane`** when Lua auto-switches tabs: otherwise update-status sees the programmatic activation as user interaction and clears the color prematurely.

## Deployment

1. Copy the hook: `config/hooks/notify-waiting.sh` → `~/.claude/hooks/notify-waiting.sh`. `chmod +x`. (One script handles both Stop and UserPromptSubmit via a `1|0` arg.)
2. Copy the PS1: `config/windows-helpers/wezterm-claude-notify.ps1` → `C:\Users\<WIN_USER>\.wezterm-claude-notify.ps1`. Edit the AUMID inside to match this machine's Claude Desktop install (see above).
3. Copy the Lua module: `config/windows-helpers/claude-waiting.lua` → `C:\Users\<WIN_USER>\.wezterm-claude-waiting.lua`. Edit `M.toast_script` to substitute `<WIN_USER>`.
4. Merge hook entries into `~/.claude/settings.json` (`Stop` async, `UserPromptSubmit` sync).
5. Wire the module into `C:\Users\<WIN_USER>\.wezterm.lua` per the three touch-points above (`dofile` + `apply()`, and the `format_tab_title_overlay` call inside the existing `format-tab-title` handler).
6. WezTerm auto-reloads. First Stop event should trigger the pipeline.

## Verification

1. Run a Claude Code session in a WezTerm tab. Stay on that pane. Send a prompt, wait for response.
   → Expected: nothing (suppression path — you're already here).
2. Switch to a different WezTerm tab. Send a prompt in the first tab.
   → Expected: tab 1 goes amber, the waiting pane within it tints warm; a toast appears. WezTerm is still focused so no window raise.
3. Switch to a different Windows app. Send a prompt.
   → Expected: toast, tab amber, pane tint, WezTerm comes to foreground on the waiting tab (pane within that tab stays as whatever was last active there).
4. Click the waiting pane → color clears immediately.
5. Use Alt+N when multiple panes are waiting → jumps to the first.
6. Submit a prompt → amber/tint clear via the UserPromptSubmit hook.

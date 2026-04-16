# Claude Waiting Notification System — Design Spec

**Date:** 2026-04-15
**Status:** Approved

## Goal

When Claude Code finishes responding and goes idle, the user needs to know — without having focus stolen mid-typing in another session. The system must:

- Play a chime sound in all cases (even if not in WezTerm)
- Highlight the waiting WezTerm tab with an amber color change (no title mutation)
- If WezTerm is not the foreground window: bring WezTerm to front and auto-switch to the waiting tab
- If WezTerm is already foreground: only highlight and sound — no focus interference
- Clear the highlight when the user submits a new prompt to that session

## Scope

- **Terminal:** WezTerm (WSL2 on Windows)
- **Trigger:** Claude Code `Stop` hook (fires when Claude enters idle state)
- **Existing hooks:** Runs alongside `agent-deck hook-handler`, both async

---

## Component 1: `notify-waiting.sh`

**Path:** `~/.claude/hooks/notify-waiting.sh`

A bash script invoked by the `Stop` hook. Performs these steps in order:

### Step 1 — Sound (unconditional)
Calls PowerShell to play a Windows system sound. This happens regardless of whether `$WEZTERM_PANE` is set, so it works even when Claude Code is run outside WezTerm.

```bash
powershell.exe -NoProfile -WindowStyle Hidden -Command \
  "[System.Media.SystemSounds]::Asterisk.Play()"
```

Note: `SystemSounds.Play()` is synchronous — it blocks until the sound completes (~1s on most systems). `-NoProfile` reduces PowerShell startup cost (~300ms saved). The sound choice (`Asterisk`) can be swapped to `Exclamation`, `Beep`, etc. To use a specific `.wav` file instead: `(New-Object Media.SoundPlayer 'C:\Windows\Media\chord.wav').PlaySync()`.

### Step 2 — Guard: check WEZTERM_PANE
`$WEZTERM_PANE` is set by WezTerm in the environment of shells launched inside it. Claude Code inherits this env var when launched from within a WezTerm pane. If unset (Claude Code launched outside WezTerm), exit here — sound already played.

```bash
[ -z "$WEZTERM_PANE" ] && exit 0
```

### Step 3 — Mark the pane
```bash
wezterm cli set-user-var --pane-id "$WEZTERM_PANE" CLAUDE_WAITING 1
```

### Step 4 — Check if WezTerm is foreground
Calls PowerShell to get the active foreground window's process name. If WezTerm is already focused, stop here — highlight and sound are sufficient.

```bash
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

# WezTerm may appear as "wezterm-gui" or "wezterm" depending on install method
case "$FOREGROUND_PROC" in
  wezterm*) exit 0 ;;
esac
```

### Step 5 — Switch tab and raise window (background case only)
First, tell WezTerm to activate the pane (switches the tab in WezTerm's own UI):
```bash
wezterm cli activate-pane --pane-id "$WEZTERM_PANE"
```

Then bring the WezTerm window to the foreground via PowerShell Win32 API:
```bash
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
    [Win32]::ShowWindow(\$proc.MainWindowHandle, 9)   # SW_RESTORE (un-minimize if needed)
    [Win32]::SetForegroundWindow(\$proc.MainWindowHandle)
  }
"
```

**Windows focus restriction note:** Windows blocks `SetForegroundWindow` from background processes in some contexts. The `ShowWindow(SW_RESTORE)` call before it works around this in most cases because restoring a window is always allowed and implicitly grants foreground rights. If it still silently fails, the fallback is taskbar flashing (the window button pulses amber) — acceptable degraded behavior.

---

## Component 2: `clear-waiting.sh`

**Path:** `~/.claude/hooks/clear-waiting.sh`

Clears the user var when the user submits a new prompt:
```bash
#!/usr/bin/env bash
[ -z "$WEZTERM_PANE" ] && exit 0
wezterm cli set-user-var --pane-id "$WEZTERM_PANE" CLAUDE_WAITING 0
```

---

## Component 3: `wezterm.lua` addition

One addition to `~/.config/wezterm/wezterm.lua`: a `format-tab-title` handler that renders waiting tabs in amber.

**Important:** WezTerm only calls one `format-tab-title` handler. If one already exists in `wezterm.lua`, this logic must be **merged into it** rather than registered as a second `wezterm.on('format-tab-title', ...)` call (the second registration would be silently ignored).

```lua
wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
  -- Check if any pane in this tab is waiting for Claude input
  local waiting = false
  -- `panes` is already scoped to this tab — no tab_id filter needed
  for _, pane in ipairs(panes) do
    if pane.user_vars.CLAUDE_WAITING == '1' then
      waiting = true
      break
    end
  end

  if waiting then
    return {
      { Background = { Color = '#e0af68' } },  -- Tokyo Night amber (matches statusline CLR_WARN)
      { Foreground = { Color = '#1a1b26' } },  -- dark text for contrast
      { Text = ' ' .. tab.active_pane.title .. ' ' },
    }
  end
  -- Return nil/nothing to use WezTerm's default tab rendering
end)
```

Note: In `format-tab-title`, `tab` and `panes` are plain Lua tables (not objects with methods). Access fields directly: `tab.tab_id`, `pane.user_vars`, `tab.active_pane.title`. `PaneInformation` entries in `panes` do **not** have a `tab_id` field — and none is needed since `panes` is already scoped to the tab being rendered. Do **not** call `tab:panes()` — that method does not exist on the tab table.

---

## Component 4: `settings.json` wiring

**`Stop` hooks** — add alongside existing `agent-deck` entry:
```json
"Stop": [
  {
    "hooks": [
      { "type": "command", "command": "agent-deck hook-handler", "async": true },
      { "type": "command", "command": "bash /home/pudge/.claude/hooks/notify-waiting.sh", "async": true }
    ]
  }
]
```

**`UserPromptSubmit` hooks** — add clear script alongside existing `agent-deck` entry. The clear script runs synchronous (`async` omitted / defaults to false) so it completes before Claude starts processing:
```json
"UserPromptSubmit": [
  {
    "hooks": [
      { "type": "command", "command": "agent-deck hook-handler", "async": true },
      { "type": "command", "command": "bash /home/pudge/.claude/hooks/clear-waiting.sh" }
    ]
  }
]
```

`clear-waiting.sh` is a fast single `wezterm cli` call (~50ms), so running it synchronously adds negligible latency before Claude responds.

---

## Edge Cases

| Scenario | Behavior |
|---|---|
| `$WEZTERM_PANE` unset (non-WezTerm terminal) | Sound plays; highlight and focus steps skipped |
| Multiple panes waiting simultaneously | Each tab shows amber independently; submitting to one clears only that pane |
| WezTerm is foreground, different pane active | Sound plays, waiting tab turns amber — no focus steal |
| User reads pane but doesn't type yet | Tab stays amber until they submit a prompt |
| `SetForegroundWindow` blocked by Windows | WezTerm tab still switches; taskbar button may flash as fallback |
| WezTerm process name is `wezterm` not `wezterm-gui` | Step 4 checks both via `case` pattern `wezterm*` |

---

## Performance Notes

- Two PowerShell calls in `notify-waiting.sh` (Steps 1 and 4/5). Each cold-starts `powershell.exe` from WSL: ~300–500ms each without `-NoProfile`, ~100–200ms with it. Total hook latency with `-NoProfile`: ~400–600ms, all async so it does not block Claude.
- `format-tab-title` is called frequently. The `user_vars` field access is a local table lookup — negligible cost.

---

## Files Changed

| File | Change |
|---|---|
| `~/.claude/hooks/notify-waiting.sh` | New — main notification script |
| `~/.claude/hooks/clear-waiting.sh` | New — clears CLAUDE_WAITING on prompt submit |
| `~/.config/wezterm/wezterm.lua` | Merge `format-tab-title` handler (or add if none exists) |
| `~/.claude/settings.json` | Add both scripts to `Stop` and `UserPromptSubmit` hooks |
| `config/hooks/notify-waiting.sh` | Repo copy (with `# <-- edit per machine: WSL username (pudge)` marker on path) |
| `config/hooks/clear-waiting.sh` | Repo copy |
| `config/settings.json` | Updated hook entries |

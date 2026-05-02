# Audit prompt: Claude Code waiting-notification system

You are auditing a feature that has already been built and is working end-to-end on the developer's machine. Your job is **not** to re-implement it. Your job is to evaluate the current implementation for correctness, robustness, maintainability, and edge cases — and flag anything that looks like latent technical debt, a hidden bug, or a design choice that deserves reconsideration.

**Model:** Opus 4.7 (same as the one that built it). You get one pass with this prompt + access to the repo at `/mnt/d/labs/claude-code-optimizations`.

---

## 1. What this system is

A notification pipeline for Claude Code sessions running inside WezTerm on Windows 11 + WSL2. When a Claude Code session finishes responding (goes idle, waiting for user input), the system surfaces that state via:

- **Tab amber** — the WezTerm tab containing the waiting session turns amber.
- **Pane bg tint** — only the specific waiting pane gets a warm `#2a2018` background.
- **Windows toast** — rendered with Claude Desktop's real icon (via AUMID spoofing).
- **Auto-switch + raise** — when WezTerm is in the background, it auto-switches to the waiting tab and raises itself to the foreground.
- **Silent suppression** — when the user is already focused on the waiting pane in a focused WezTerm, nothing at all happens (no toast, no amber, no tint).

The state clears on: prompt submit, click in the pane, activating a different pane via keyboard, or hitting Alt+N to jump to the next waiting pane.

## 2. Goal

Help the developer multitask with multiple concurrent Claude Code sessions without having to poll each one. Give enough signal to notice "something finished" without interrupting what they're currently doing.

## 3. Requirements (what "working" means)

### Functional

1. Each WezTerm pane with a Claude Code session has independent waiting state. Three concurrent sessions → three independent amber/tint states.
2. **Tab header is amber** iff *any* pane in that tab has `CLAUDE_WAITING=1`.
3. **Pane bg is tinted** only on the specific waiting pane, not siblings in the same tab.
4. On Stop, a Windows toast fires with:
   - Title: `Claude Code`
   - Body: `<project-name> - waiting for input`
   - Icon: Claude Desktop's icon (via AUMID)
   - Sound: the toast's built-in default (not a separate `SystemSounds::Asterisk`)
5. **Auto-switch tab, not pane**. When WezTerm is raised from the background, it switches to the tab containing the waiting pane but does NOT change which pane is active inside that tab. The user must manually navigate to the waiting pane (learning WezTerm pane shortcuts is intentional).
6. **Suppression**: if at the moment of Stop, the user is (a) on the waiting pane and (b) WezTerm is focused, no notification of any kind fires.
7. **Don't steal focus** when WezTerm is already focused (no raise, no tab switch) — only tint/amber.
8. **Clear triggers**:
   - Bash `UserPromptSubmit` hook — user sent a reply.
   - WezTerm mouse binding — user left-clicked inside the waiting pane.
   - WezTerm `update-status` handler — user activated a different pane (keyboard nav, tab switch, Alt+N).
9. **Alt+N**: jumps to the first pane (across all tabs) with `CLAUDE_WAITING=1`. Acts as both a tab switch and a pane switch.

### Non-functional

- Bash hooks must be async (Stop) or near-instant (UserPromptSubmit) so Claude's UI isn't blocked.
- Single source of truth for clearing: all writers just flip the OSC user var; the Lua event handler handles bg reset on value=0.
- No sound doubling (one sound total per notification).
- Must survive WezTerm's automatic config reload.
- The system should degrade gracefully if WezTerm isn't running (bash hooks should still complete).

## 4. Architecture

```
┌───────────────────────────────────┐
│ Stop hook (bash)                  │ notify-waiting.sh
│  → OSC 1337 SetUserVar=1          │
│                                   │
│ UserPromptSubmit hook (bash)      │ clear-waiting.sh
│  → OSC 1337 SetUserVar=0          │
└────────────────┬──────────────────┘
                 │ OSC bytes written to the pane's /dev/pts/N
                 ▼
┌───────────────────────────────────┐
│ WezTerm terminal emulator         │
│  - parses OSC 1337                │
│  - updates pane user_vars map     │
│  - fires `user-var-changed` event │
│  - re-renders tab title           │ format-tab-title reads user_vars
└────────────────┬──────────────────┘
                 │
                 ▼
┌───────────────────────────────────┐
│ wezterm.lua user-var-changed      │ decides: suppress vs alert
│  (value=1)                        │
│  ├─ is user on this pane + win    │
│  │    focused? → clear var, done. │
│  ├─ else: tint bg (OSC 11)        │
│  ├─ if !focused: auto-switch tab  │
│  │    + preempt last_active_pane  │
│  ├─ spawn PowerShell for toast    │
│  │    (+raise if !focused)        │
│  └─ return                        │
│                                   │
│  (value=0) reset bg tint (OSC 111)│ single source for bg reset
└────────────────┬──────────────────┘
                 │
                 ▼
┌───────────────────────────────────┐
│ PowerShell .wezterm-claude-notify │ pure toast + optional raise
│  ├─ Windows.UI.Notifications toast│
│  │    with AUMID → Claude icon    │
│  └─ if -Raise: SetForegroundWindow│
│       (with fake Alt tap to       │
│       bypass focus-steal protect) │
└───────────────────────────────────┘
```

Additional clear paths (in wezterm.lua):

- **`update-status` #1 (claude clearing)**: fires ~1/s per window. If the active pane changed since last tick and the new active pane has `CLAUDE_WAITING=1`, clear it. Handles keyboard nav / tab switch.
- **Mouse binding on `Up Left` with `mods=NONE`**: if the clicked pane has `CLAUDE_WAITING=1`, clear it. Also performs the default selection-completion action so copy-on-click still works. Handles click-in-same-pane case which `update-status` misses.
- **`Alt+N` keybinding**: iterates all tabs/panes across the window, calls `pane:activate()` on the first with `CLAUDE_WAITING=1`. Activation triggers `update-status` clearing path naturally.

## 5. File inventory

### Linux side (`~/.claude/hooks/`)

- **`notify-waiting.sh`** (Stop hook, async)
  - Walks process tree via `/proc/PID/fd/` until a `/dev/pts/*` symlink is found.
  - Writes `\e]1337;SetUserVar=CLAUDE_WAITING=MQ==\a` (base64 `1`) to that pty.
  - Nothing else. All decision logic lives in wezterm.lua.

- **`clear-waiting.sh`** (UserPromptSubmit hook, sync)
  - Same tty walk.
  - Writes `\e]1337;SetUserVar=CLAUDE_WAITING=MA==\a` (base64 `0`).
  - Bg reset happens in the Lua `user-var-changed` handler.

### Windows side (`C:\Users\<WIN_USER>\`)

- **`.wezterm-claude-notify.ps1`** — PowerShell toast helper.
  - `param([string]$Label, [switch]$Raise)`
  - Creates a `Windows.UI.Notifications.ToastNotification` via WinRT, displays it through a notifier bound to Claude Desktop's AUMID (machine-specific — e.g. `Claude_pzs8sxrjxfjjc!Claude`).
  - If `-Raise`: uses `keybd_event` to simulate an Alt keypress, then calls `SetForegroundWindow` on the wezterm-gui process.
  - Sanitizes the `$Label` to strip XML-injectable characters.

- **`.wezterm.lua`** — WezTerm configuration (Windows path; WezTerm does not read `~/.config/wezterm/` under WSL).
  - Helpers at top: `CLAUDE_WAITING_BG`, `CLAUDE_TOAST_SCRIPT` (path), `claude_clear_waiting(pane)`.
  - `format-tab-title` — amber logic using `wezterm.mux.get_tab(tab.tab_id):panes()`.
  - `user-var-changed` — the orchestration handler described above.
  - `update-status` #1 — pane-activation-change clearing.
  - `update-status` #2 — the existing right status bar rendering.
  - `config.keys[]` — Alt+N entry.
  - `config.mouse_bindings[]` — left-click-up entry with callback.

### Claude Code settings (`~/.claude/settings.json`)

Hook wiring (merge alongside any existing entries):

```json
{
  "hooks": {
    "Stop": [{
      "hooks": [{ "type": "command", "command": "bash /home/<WSL_USER>/.claude/hooks/notify-waiting.sh", "async": true }]
    }],
    "UserPromptSubmit": [{
      "hooks": [{ "type": "command", "command": "bash /home/<WSL_USER>/.claude/hooks/clear-waiting.sh" }]
    }]
  }
}
```

### Repo copies

Under `/mnt/d/labs/claude-code-optimizations/`:

- `config/hooks/notify-waiting.sh`
- `config/hooks/clear-waiting.sh`
- `config/windows-helpers/wezterm-claude-notify.ps1` (note: `windows-helpers/` is a bespoke dir — this half of the feature doesn't fit the `~/.claude/` mirror convention)
- `changelogs/CHANGELOG-2026-04-16-claude-waiting-notification.md`

## 6. Key design decisions

### Signal: OSC 1337 SetUserVar

WezTerm supports iTerm2's OSC 1337 SetUserVar escape sequence. Writing `\e]1337;SetUserVar=NAME=BASE64VALUE\a` to a pane's pty sets a named string on that pane, accessible from Lua via `pane:get_user_vars()`. This is the signal we use for `CLAUDE_WAITING`.

`wezterm.exe cli set-user-var` does **not** exist — it was considered and rejected. The OSC approach is the documented method.

### Why the logic lives in Lua, not bash

Deciding whether to suppress requires knowing: (a) is WezTerm the foreground window, (b) is the waiting pane the active pane of the active tab in that window. Bash has no reliable way to know "my pane ID" — `WEZTERM_PANE` is not propagated into WSL shells. `wezterm.exe cli list` shows `tty_name: null` for all panes, breaking a TTY-based mapping. Rather than round-trip through file-based side-channels, all decision logic moved to Lua, where `window:active_pane()` and `window:is_focused()` are directly available on the event object.

### Single source of truth for bg reset

All writers (bash hooks, mouse binding, update-status, self-suppression) just flip `CLAUDE_WAITING` via `claude_clear_waiting(pane)`. That triggers `user-var-changed` with value=0, which writes OSC 111 (reset default bg). So any path that clears the var also clears the bg, with no duplicated OSC-111 calls scattered through the codebase.

### Preempt `last_active_pane` on auto-tab-switch

When Lua programmatically activates the waiting pane's tab (in the not-focused branch), that tab's "last active pane" may be the waiting pane itself, which means the window's active pane just changed to the waiting pane. The `update-status` clearing logic would see this as a user activation and immediately clear the tint. To avoid this, we write the new active pane ID into `wezterm.GLOBAL.last_active_pane[window_id]` right after `mux_tab:activate()`, so `update-status` thinks nothing changed.

### Window raise via fake Alt tap (not `window:focus()`)

Windows 10/11 block `SetForegroundWindow` from non-foreground processes (focus-stealing protection). The standard 20+ year workaround: simulate an Alt keypress via `keybd_event(VK_MENU, ...)` before calling `SetForegroundWindow`, which tricks Windows into thinking the user initiated the action. We tried `window:focus()` from Lua first (inside WezTerm's own context, so theoretically not subject to the restriction), but empirically it does not raise when WezTerm is already backgrounded.

### Claude Desktop AUMID for toast identity

Windows toasts show under whatever app registered the AppUserModelID passed to `CreateToastNotifier`. Claude Desktop registers an AUMID like `Claude_pzs8sxrjxfjjc!Claude` (the hash segment is per-install). By passing this AUMID, the toast appears as if sent by Claude itself — correct icon, correct branding — even though it's actually fired from PowerShell. Equivalent of the macOS `terminal-notifier -sender com.anthropic.claudefordesktop` trick.

## 7. Issues encountered during development + fixes

Read these before diving in. Many are non-obvious and explain why the code is shaped the way it is.

1. **Wrong wezterm.lua path.** First attempt created the Lua config at WSL path `~/.config/wezterm/wezterm.lua`. WezTerm is a Windows application; it reads from `C:\Users\<WIN_USER>\.wezterm.lua` and never consults the WSL path. Moved the file; deleted the WSL copy.

2. **`wezterm.exe cli set-user-var` doesn't exist.** The first hooks used this command and failed silently. Replaced with direct OSC 1337 writes to `/dev/pts/N`.

3. **TTY discovery via process tree.** Hooks run as Claude Code subprocesses with redirected stdin/stdout/stderr. `tty` returns "not a tty." Solution: walk `/proc/PID/fd/` for 0/1/2 symlinks pointing to `/dev/pts/*`, and if nothing found, climb via `/proc/PID/status` PPid. First pts hit wins.

4. **All tabs turned amber.** First `format-tab-title` used the `panes` parameter directly, which spans the entire WezTerm **window** (all tabs), not the current tab. Any `CLAUDE_WAITING=1` pane made every tab amber. Fixed with `wezterm.mux.get_tab(tab.tab_id):panes()`, which is scoped to the current tab and also returns **live** user_vars (unlike `tab.active_pane.user_vars`, which is a stale snapshot).

5. **`tab.active_pane.user_vars` is stale.** An intermediate fix checked `tab.active_pane.user_vars.CLAUDE_WAITING == "1"` and found it never matched, because WezTerm's `TabInformation.active_pane` carries a snapshot, not live state. Current code uses `pane:get_user_vars()` on mux Pane objects.

6. **`MuxTab:panes()` returns Pane objects directly.** An intermediate version wrote `pane_info.pane:get_user_vars()` assuming a wrapper struct. WezTerm's `MuxTab:panes()` returns raw Pane objects, so `pane_info.pane` is nil. Error log: `attempt to index a nil value (field 'pane')`. Fixed to iterate directly.

7. **Em-dash broke PowerShell parsing.** The toast body originally used "—" (U+2014) between project name and "waiting for input." PowerShell (Windows PS 5.1) read the PS1 file without BOM and mis-decoded the em-dash, which threw off the XML string parser at `$xml.LoadXml(...)`. Replaced with ASCII `-`.

8. **Focus-stealing protection blocked window raise.** Initial raise logic used `SetForegroundWindow` directly and silently failed when WezTerm was backgrounded. Added the standard `keybd_event` fake-Alt-tap workaround before the call.

9. **`window:focus()` is a no-op when backgrounded.** Tried moving the raise to Lua via `window:focus()`, expecting that "WezTerm raising itself" bypasses focus-stealing protection. Empirically it didn't. Reverted to the PowerShell path with keybd_event.

10. **Auto-tab-switch prematurely cleared color.** When the not-focused branch activated the waiting pane's tab, and that tab's last-active pane was the waiting pane, `update-status` saw this as a user activation and cleared the waiting state before the user could even see it. Fix: write the new active pane ID into `wezterm.GLOBAL.last_active_pane[window_key]` immediately after `mux_tab:activate()`.

11. **Click-in-same-pane didn't clear.** If the user was already on the waiting pane, clicking it again didn't change the active pane, so `update-status` saw no transition and didn't clear. Added a `config.mouse_bindings` entry on `{Up, Left, mods=NONE}` with a callback that clears the var if set, then performs the default `CompleteSelectionOrOpenLinkAtMouseCursor` so copy-on-click still works.

12. **AUMID is per-install.** The Claude Desktop AUMID contains a machine-specific hash segment (`Claude_pzs8sxrjxfjjc!Claude` in this developer's case). Must be discovered per-machine via `powershell.exe Get-StartApps | Where-Object Name -like '*Claude*'`.

13. **Double sound.** First version played `[System.Media.SystemSounds]::Asterisk` and also showed a toast (which plays its own default sound on Windows 11), resulting in two distinct notification sounds. Removed the explicit Asterisk call; kept the toast's native sound.

14. **Single `format-tab-title` handler.** WezTerm only fires the last-registered `format-tab-title` handler. The amber logic must be merged into whatever existing handler the user has (tab index + title formatting), not added as a separate registration.

## 8. What to audit — questions to answer

Read the code and evaluate each of the following. Don't just confirm the system works — look for what could go wrong and what hasn't been stress-tested.

### Correctness / robustness

- [ ] Are there race conditions between the `user-var-changed` event firing and the bg tint being applied? What if Claude Code outputs something between the OSC parse and the next render?
- [ ] What happens if the user closes the waiting pane before responding? Does `CLAUDE_WAITING=1` stick somewhere?
- [ ] What happens if the user drags the waiting pane to a different tab or window? Does the pane's user_var travel with it? Does the amber?
- [ ] If WezTerm restarts while a session was waiting, what state is left over? The `wezterm.GLOBAL.last_active_pane` table is persistent across reloads — is there any way it gets out of sync?
- [ ] The `find_tty` walk iterates via `PPid`. What happens if the process tree is unusual (e.g., Claude Code runs inside `tmux` or `mosh` or `ssh`)? Does it find the right pts?
- [ ] The OSC 111 bg reset — is it guaranteed to restore to Tokyo Night's `#1a1b26`? What if a theme changes while a pane is tinted?
- [ ] Does the mouse binding swallow the default `Up Left` action in any scenario that breaks normal selection copy?

### Edge cases

- [ ] Two panes in the same tab both become waiting at once. The tab is amber (OK). Each pane tinted (OK). User clicks into pane A — does the tab stay amber (because pane B is still waiting)?
- [ ] User has 3 WezTerm windows open. Session in window 2 becomes waiting. Does raise target the right window? Does `Get-Process wezterm-gui | Select -First 1` return the right one?
- [ ] User runs Claude Code on a non-WezTerm terminal (accidentally). The bash hook still fires. The OSC write goes to a pty that no WezTerm window is reading. Does anything break, or is it a silent no-op?
- [ ] Session with an unusually deep process tree — `find_tty` has no depth limit. Can it infinite-loop? (PPid hits PID 1 and breaks.)
- [ ] Toast body label — what if CWD contains XML-special characters or PowerShell-injectable strings? `-replace '[<>&"''`]'` covers the obvious; are there bypasses?
- [ ] `wezterm.background_child_process` — if it fails (PowerShell path wrong, etc.), does the failure propagate anywhere the user sees it, or is it silently swallowed?
- [ ] Alt+N when no pane is waiting — no-op (OK) or does it change the active pane to something unexpected?

### Maintainability

- [ ] The logic is split between bash, Lua, and PowerShell. Is it understandable? Could anything be consolidated?
- [ ] The `CLAUDE_TOAST_SCRIPT` path is hardcoded to `C:\Users\spirit\` — is the `<-- edit per machine` marker clear enough?
- [ ] The AUMID is hardcoded in the PS1. Machine-specific. The changelog documents this, but someone applying this to a new machine needs to remember the `Get-StartApps` step.
- [ ] Two `update-status` handlers are registered on the same event. Is this obvious to a future reader?
- [ ] Is anything here fragile to WezTerm version changes? Which APIs are newest (likely `wezterm.background_child_process`, `window:is_focused()`, `pane:tab()`, `MuxTab:panes()`)?

### Security

- [ ] The PS1 executes with whatever privileges WezTerm has. Can a malicious Claude output inject into the toast label? (Label comes from `pane:get_current_working_dir()` — user-controlled paths.)
- [ ] Mouse-binding callback runs on every left-click release. Does it allocate / leak anything?

### Things that were considered and rejected (don't re-propose these)

- Chime via `[System.Media.SystemSounds]::Asterisk` — replaced with toast's built-in sound.
- `wezterm.exe cli set-user-var` — does not exist.
- Detecting "user typing" via cursor position change — deferred (user explicitly said not now).
- UI Automation (UIA) focused-element check for "user is in a text input" — deferred.
- `window:focus()` from Lua to raise WezTerm — doesn't work when backgrounded.
- Auto-switching to the waiting pane within a tab — intentionally left manual (user wants to practice keyboard shortcuts).
- Per-pane title marker (e.g. `⚠` prefix) — user rejected.
- Sidebar TUI (wezterm-agent-cards style) — rejected as too complex for current need.
- Tmux/zellij migration — not needed, WezTerm's OSC 11 does per-pane tinting fine.

## 9. Output format

Produce a single audit report as markdown. Structure:

```
# Audit findings

## Summary
<one-paragraph overall take>

## Critical issues (must fix)
<things that are genuinely broken or dangerous>

## Significant issues (should fix)
<bugs, race conditions, fragile assumptions>

## Minor observations
<cleanups, naming, comment drift, style>

## Questions for the developer
<things unclear from the code alone — context you'd need>

## Things done well
<what's actually solid — don't skip this section>
```

Be specific. File paths + line ranges. Don't hedge with "might" unless you actually ran the code and aren't sure.

Do not make any code changes. This is a read-only audit.

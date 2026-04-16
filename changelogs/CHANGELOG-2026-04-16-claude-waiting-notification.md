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

# statusline — setup

**Requires:** Claude Code, bash

## Per-machine values

- `<LINUX_USER>` — your WSL username (appears in `~/.claude/settings.json` `statusLine.command`, not in this script itself)
- `<TIMEZONE>` — your local TZ; the script ships with the literal `America/Chicago` (4 occurrences in `statusline-command.sh`, each marked `edit per machine`)

## Files

- `statusline-command.sh` → deploys to `~/.claude/statusline-command.sh` (chmod +x)

## Install

1. `cp statusline-command.sh ~/.claude/statusline-command.sh`
2. Substitute your timezone for the shipped `America/Chicago` literal (e.g. `sed -i 's|America/Chicago|Europe/Berlin|g' ~/.claude/statusline-command.sh`).
3. `chmod +x ~/.claude/statusline-command.sh`
4. Confirm `~/.claude/settings.json` `statusLine.command` references `bash /home/<LINUX_USER>/.claude/statusline-command.sh`. (`baseline-settings` does this by default.)

## Verify

Launch Claude Code in any directory. The status bar should render two lines (model + tokens line, rate-limits line) at the bottom.

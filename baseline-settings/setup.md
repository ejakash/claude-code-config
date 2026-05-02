# baseline-settings — setup

**Requires:** Claude Code

## Per-machine values

- `<WSL_USER>` — your WSL username (appears in `statusLine.command` path)

## Files

- `settings.json` (JSONC) → deploys to `~/.claude/settings.json` (merge if file exists; do not overwrite blindly)

## Install

1. If `~/.claude/settings.json` does not exist: copy this module's `settings.json` after substituting `<LINUX_USER>` with your WSL username (sed `s|<LINUX_USER>|<YOUR_WSL_USER>|g`).
2. If `~/.claude/settings.json` exists: merge keys. The user's existing entries take precedence on conflicts; ask before overwriting any keys that already have a value.
3. The file is JSONC (contains `//` comments); Claude Code accepts this natively. To spot-check, strip comments first: `grep -v '^\s*//' ~/.claude/settings.json | python3 -c "import sys,json; json.load(sys.stdin)"` (inline comments on value lines may still cause errors — visual review is sufficient).

## Verify

- `claude --version` runs without errors.
- Status bar renders (the `statusline-command.sh` deployed by the `statusline` module).
- Permissions allow-list applies (e.g. `git status` doesn't prompt).

## Uninstall

Remove the keys this module added; restore the user's prior `~/.claude/settings.json` from backup if available.

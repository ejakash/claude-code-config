# statusline

Two-line Tokyo Night status bar for Claude Code: model, tokens, context, cost, rate limits.

Wired into `~/.claude/settings.json` via the `statusLine.command` field — the `baseline-settings` module already points there, so install order matters (statusline before baseline-settings, OR install statusline first and have baseline-settings reference it).

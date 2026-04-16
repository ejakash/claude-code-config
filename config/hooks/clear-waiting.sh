#!/usr/bin/env bash
# Claude Code UserPromptSubmit hook — clear CLAUDE_WAITING when user replies
# Repo copy. The machine-specific path is in config/settings.json (<-- edit per machine).

[ -z "${WEZTERM_PANE:-}" ] && exit 0
wezterm cli set-user-var --pane-id "$WEZTERM_PANE" CLAUDE_WAITING 0

# statusline

Two-line Tokyo Night status bar for Claude Code.

- **Line 1:** dir · model · session-cumulative tokens (`in` uncached, `out` generated, `r` cache reads, `w` cache writes, `hit %`) · context used/total · cost
- **Line 2:** cache-write TTL split (`5m` / `1h`) · 5h and 7d rate-limit bars with reset times · session duration

Cumulative token numbers are summed from the session JSONL transcript (`~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`) — the statusline input JSON only carries current-context usage and doesn't expose the 5m/1h TTL split. Falls back to `context_window.current_usage` when the transcript isn't readable. Known caveat: the transcript logs one assistant row per inner iteration, so cumulative totals over-count versus billable usage (see `followup-statusline-cache-display.md` at the repo root for the analysis and open questions).

Wired into `~/.claude/settings.json` via the `statusLine.command` field — the `baseline-settings` module already points there, so install order matters (statusline before baseline-settings, OR install statusline first and have baseline-settings reference it).

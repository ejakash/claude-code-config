# Setup — `claude-code-optimizations`

This repo holds Claude Code configuration as independently-installable modules. The agent walks the module list with you and installs only what you want.

## Per-machine values (collected once up front)

- `<WSL_USER>` — your WSL username (e.g. `pudge`)
- `<WIN_USER>` — your Windows username (e.g. `spirit`)
- `<TIMEZONE>` — your local TZ (e.g. `America/Chicago`)

## Modules

| Module | What it does | Requires |
|---|---|---|
| `baseline-settings/` | `~/.claude/settings.json` baseline (permissions, plugins, model, statusline pointer, agent-deck hooks) | Claude Code |
| `statusline/` | Two-line Tokyo Night status bar | Claude Code, bash |
| `claude-md/` | Global agent instructions in `~/.claude/CLAUDE.md` | Claude Code |

**Ordering:** install `baseline-settings` and `statusline` before any cross-cutting module that registers hooks in `settings.json` (e.g. `claude-waiting-notification`).

## See also (cross-cutting tools)

- **claude-waiting-notification** — Stop-hook + WezTerm Lua + Windows toast for idle Claude Code sessions. Requires WSL2 + WezTerm + Win11.
  `<TBD: github URL once published>`
- **auto-screenshot** — Window-aware screen capture skill for Windows hosts. Requires Windows + PowerShell.
  `<TBD: github URL once published>`
- **spawn-session** — Fan a batch of independent tasks into N Claude Code processes, each in its own WezTerm pane. Requires WezTerm + Claude Code.
  `<TBD: github URL once published>`

## Sync

After `git pull`, ask the agent to "sync" / "update" this repo. Sync state is a machine-local git tag `synced-on-<hostname>`:

- Tag exists → agent shows `git log synced-on-<hostname>..HEAD --stat` (substitute your actual hostname, e.g. `synced-on-navi`), walks per-module deltas, applies what you accept, then `git tag -f synced-on-<hostname>` at HEAD.
- Tag missing (fresh clone) → agent treats as fresh setup and walks the module menu above. If a module was removed upstream, the agent will ask before removing anything from your machine — declined modules don't get re-offered.

The tag is local-only (tags don't push by default). User-driven `git pull` outside the agent is fine — the tag still points at the last commit you actually synced.

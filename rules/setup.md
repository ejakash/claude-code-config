# rules — setup

**Requires:** Claude Code. The `dotnet.md` rule additionally assumes WSL with ReSharper CLI installed as a .NET global tool on the Windows side (`jb.exe`); skip that file on machines without it.

## Per-machine values

- `<WINDOWS_USER>` — your Windows username; appears in the `jb.exe` interop paths inside `dotnet.md`.

## Files

- `dotnet.md` → `~/.claude/rules/dotnet.md`
- `python.md` → `~/.claude/rules/python.md`
- `frontend.md` → `~/.claude/rules/frontend.md`
- `parse-sarif.py` → `~/.claude/scripts/parse-sarif.py`

## Install

1. `mkdir -p ~/.claude/rules ~/.claude/scripts`
2. Copy the three rule files into `~/.claude/rules/`, substituting `<WINDOWS_USER>` in `dotnet.md`.
3. `cp parse-sarif.py ~/.claude/scripts/parse-sarif.py`
4. If installing `dotnet.md`, keep the ".NET Code Quality" pointer section in `~/.claude/CLAUDE.md` (the `claude-md` module ships it); if skipping, drop that section too.

## Verify

Open a Claude Code session in a .NET repo and touch a `.cs` file — the agent should know about `jb inspectcode` and the `parse-sarif.py` workflow. In a non-.NET repo, the rule should not load (ask the agent about `jb` — it shouldn't cite the rule).

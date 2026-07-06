# rules

Path-scoped language rules for `~/.claude/rules/`, plus the SARIF parser script the .NET rule depends on.

Each rule file carries a `paths:` frontmatter block, so Claude Code only loads it when the session touches matching files — .NET guidance costs nothing in a Python session and vice versa. This keeps the global `CLAUDE.md` lean: domain-specific workflow detail lives here, conditionally loaded, instead of in the always-loaded global instructions.

- `dotnet.md` — LSP-first navigation, solution-level build/test, ReSharper CLI (`jb inspectcode` / `cleanupcode`) usage and required SARIF parsing.
- `python.md` — LSP navigation, no `python -c` file manipulation, venv awareness.
- `frontend.md` — LSP navigation, package-manager scripts over ad-hoc node.
- `parse-sarif.py` — shared parser for `jb inspectcode` SARIF output; deploys to `~/.claude/scripts/`.

---
paths:
  - "**/pyproject.toml"
  - "**/requirements*.txt"
  - "**/setup.py"
  - "**/setup.cfg"
  - "**/*.py"
---

# Python / ML

## Navigation
- Use LSP for navigation and type diagnostics when available.

## Commands
- Use Bash for running actual Python programs and scripts.
- Never use `python -c` for file manipulation — use Edit/Grep/Glob instead.
- Be aware of virtual environments. Check for venv/conda before installing packages.

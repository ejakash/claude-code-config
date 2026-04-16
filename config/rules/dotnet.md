---
paths:
  - "**/*.sln"
  - "**/*.slnx"
  - "**/*.csproj"
  - "**/*.props"
  - "**/*.targets"
  - "**/*.cs"
---

# .NET Development

## Navigation
- Use LSP for semantic navigation (go-to-definition, find-references, rename) when available.
- Fall back to Grep only if LSP is unavailable or returns no results.

## Build and test
- Use `dotnet build <solution>` and `dotnet test <solution>` on the solution file, not per-project.
- Use absolute paths or `--project` flags. Do not `cd` into project directories.

## JetBrains ReSharper CLI

`jb` is available via Windows interop at `/mnt/c/Users/spirit/.dotnet/tools/jb.exe`. Use this path directly or add to PATH: # <-- edit per machine: Windows username (spirit)

```bash
export PATH="$PATH:/mnt/c/Users/spirit/.dotnet/tools" # <-- edit per machine: Windows username (spirit)
```

Or use the `/inspect` skill which handles this automatically.

Run `jb inspectcode` only when a feature or fix is complete — not mid-implementation. Incomplete code produces false positives (unused variables, etc.) that waste time.

Syntax: all flags BEFORE the solution file. Values use `=` (no spaces). Solution file is always the LAST argument.

```
/mnt/c/Users/spirit/.dotnet/tools/jb.exe inspectcode -o="inspect-results.json" -f="Sarif" -e="WARNING" <solution-file> # <-- edit per machine: Windows username (spirit)
```

### Parsing results (REQUIRED after every inspectcode run)

Use the shared parser script — do NOT inline Python or shell one-liners:

```bash
python3 ~/.claude/scripts/parse-sarif.py inspect-results.json --min-level warning
rm inspect-results.json
```

The script:
- Filters out generated files (obj/, bin/, *.g.cs, AssemblyInfo.cs, etc.)
- Prints `[LEVEL] file:line (RuleId) — message` for each issue
- Exits 0 if clean, 1 if issues found

After reviewing results: fix issues, re-run inspectcode to verify, then delete the results file.

For auto-formatting specific files:
```
/mnt/c/Users/spirit/.dotnet/tools/jb.exe cleanupcode <solution-file> --include="**/ChangedFile.cs" # <-- edit per machine: Windows username (spirit)
```

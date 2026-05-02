## Speech-to-Text Input

The user dictates using speech-to-text (STT). This causes predictable transcription errors on technical terms:

- **"Cloud code"** → means **Claude Code** (the CLI tool)
- **"Cloud"** alone in a technical context → likely **Claude**
- Other misrecognized terms may appear — use context to infer the intended word

Do not be confused by these substitutions. Interpret commands as the user intended.

---

## Tool usage

- Prefer built-in tools over Bash for file/search operations:
  - Read over cat/head/tail
  - Grep/Glob over grep/find/xargs
  - Edit (with replace_all) over sed/awk for find-and-replace
- Use LSP for semantic navigation (definitions, references, symbols) when available. Fall back to Grep only if LSP doesn't cover the language.

## Command hygiene

- Avoid compound Bash statements (cd X && cmd). Use absolute paths or tool flags instead (e.g., `git -C <path>`, `dotnet build <path>`).
- Do not use `cd` unless the tool genuinely requires the working directory to be set.
- One command per Bash call when possible.

## Screenshots

The user's screenshots folder is `C:\Users\<WINDOWS_USER>\Pictures\Screenshots` (WSL path: `/mnt/c/Users/<WINDOWS_USER>/Pictures/Screenshots`). <!-- edit per machine: Windows username -->

- When the user says **"look at the screenshot"** or **"look at the last screenshot"** → read the **1 most recent** file from that folder.
- When the user says **"look at the last two screenshots"** → read the **2 most recent** files.
- When the user says **"look at the last screenshots"** (plural, no number) → read all files modified within the **last 2 minutes**.
- Determine recency by file modification time (use `ls -t` or Glob sorted by modification time).
- **Only read the exact number of files requested.** Do not read additional files from this folder — the folder contains all Windows screenshots and most will be irrelevant to the current conversation.

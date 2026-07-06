## Speech-to-Text Input

The user dictates using speech-to-text (STT). This causes predictable transcription errors on technical terms:

- **"Cloud code"** → means **Claude Code** (the CLI tool)
- **"Cloud"** alone in a technical context → likely **Claude**
- Other misrecognized terms may appear — use context to infer the intended word

Do not be confused by these substitutions. Interpret commands as the user intended.

---

## Tool usage

- Prefer built-in tools over Bash for file/search operations — they're faster and don't require permission prompts:
  - Read over cat/head/tail
  - Grep/Glob over grep/find/xargs
  - Edit (with replace_all) over sed/awk for find-and-replace
- Use Bash cat/grep/find/xargs when the task genuinely calls for it — piped transformations, multi-step shell expressions, or cases where built-in tools can't handle it cleanly.
- Use LSP for semantic navigation (definitions, references, symbols) when available. Fall back to Grep only if LSP doesn't cover the language. When using the fallback, surface the fact to the user (e.g. "LSP unavailable for this language, falling back to Grep").

## Command hygiene

- Avoid compound Bash statements (cd X && cmd). Use absolute paths or tool flags instead (e.g., `git -C <path>`, `dotnet build <path>`).
- Do not use `cd` unless the tool genuinely requires the working directory to be set.
- One command per Bash call when possible.

## Git

- Do not add AI-attribution footers to git commits or PRs: no `Co-Authored-By: Claude …` trailer on commit messages, and no "🤖 Generated with Claude Code" line on PR bodies. (Overrides the default commit-message and PR conventions.)

## Screenshots

The user's screenshots folder is `C:\Users\<WINDOWS_USER>\Pictures\Screenshots` (WSL path: `/mnt/c/Users/<WINDOWS_USER>/Pictures/Screenshots`). <!-- edit per machine: Windows username -->

- When the user says **"look at the screenshot"** or **"look at the last screenshot"** → read the **1 most recent** file from that folder.
- When the user says **"look at the last two screenshots"** → read the **2 most recent** files.
- When the user says **"look at the last screenshots"** (plural, no number) → read all files modified within the **last 2 minutes**.
- Determine recency by file modification time (use `ls -t` or Glob sorted by modification time).
- **Only read the exact number of files requested.** Do not read additional files from this folder — the folder contains all Windows screenshots and most will be irrelevant to the current conversation.

## .NET Code Quality

<!-- requires the rules/ module (ships ~/.claude/rules/dotnet.md); omit on machines without it -->

When working on .NET projects (any .sln/.slnx), use ReSharper CLI for code analysis. See `~/.claude/rules/dotnet.md` for detailed usage.

## View markdown deliverables in the themed viewer

<!-- requires the wezterm-webview viewer; omit on machines without it -->

`view <path>` opens a file in the wezterm-webview viewer pane (the themed,
chromeless WebView2 pane docked beside WezTerm; see `/mnt/d/labs/wezterm-webview`).

- After **preparing a markdown deliverable** (a spec, plan, design doc, report, or
  similar) for the user, run `view <absolute-path>` so it opens in the viewer.
- For an **existing markdown file** I'm pointing the user at, offer to open it and
  run `view` on confirmation.
- Best-effort only: use an **absolute path**, run it detached, and **never block or
  treat a failure as fatal** (the viewer may not be set up in every environment).

## Claude Code notification "do not disturb"

<!-- requires claude-waiting-notification (and its claude-dnd.sh); omit on machines without it -->

The WezTerm-side waiting-notification (toast + window raise when Claude finishes or
needs input) can be paused per session via `~/.claude/scripts/claude-dnd.sh`. The
pause is global while active and owned by the session that set it; it clears when
that session ends or on an explicit resume.

- When the user says **"don't disturb me"** / **"mute notifications"** / **"dnd on"** /
  **"I'm gaming"** → run `bash ~/.claude/scripts/claude-dnd.sh on` and confirm briefly.
- When the user says **"resume"** / **"notifications back on"** / **"dnd off"** →
  run `bash ~/.claude/scripts/claude-dnd.sh off` and confirm.

Specific apps (e.g. Dota) are silenced automatically via
`C:\Users\<WINDOWS_USER>\.wezterm-claude-dnd-apps.txt` — no command needed; just add the <!-- edit per machine: Windows username -->
process name to that file.

# Modular Reorg — Curated Index → Module Folders + Cross-Cutting Repos

**Date:** 2026-05-02
**Status:** Design pending review

## Problem

The current `claude-code-optimizations` repo is a single curated reference for Claude Code (`~/.claude/`) configuration, structured as event-sourcing: `CHANGELOG-SUMMARY.md` indexes per-change `changelogs/*.md` files, `.changelog-status` tracks per-machine review state, `SETUP-GUIDE.md` is the accumulated baseline. The same pattern is mirrored in the sibling `wezterm` repo.

Three issues with the current shape:

1. **Components are not visible.** Tools live as scattered files inside `config/` (`hooks/`, `rules/`, `skills/`, `windows-helpers/`, `scripts/`); the only narrative for each tool is its changelog entry. To understand what a tool is, you must reconstruct it across the file tree and the changelog.
2. **Opinions change over time and the structure resists removal.** Two concrete examples: the `pretooluse-bash-guardrails.py` hook and the `check-cs-edit.py` C# auto-formatting reminder no longer carry their weight — the agent does the right thing without them — but they are tangled into `settings.json` alongside still-useful hooks, with their motivations only partly recoverable from changelogs. The C# inspectcode → `parse-sarif.py` → agent-fixes-issues loop was tuned heavily on the personal PC, never ported to the work PC, and proved unnecessary in practice.
3. **Cross-cutting tools have no clean home.** `claude-waiting-notification` (CC hook + WezTerm Lua + Windows toast PS1) and `auto-screenshot` (CC skill + Windows-side PowerShell capture) span CC + WezTerm + Windows. They live in `claude-code-optimizations` today by default, but they are not "Claude Code config" in the same sense `settings.json` and `statusline-command.sh` are. The sibling `spawn-session/` repo (already split) shows the natural shape for cross-cutting tooling: own repo, no event-sourcing meta, just the files.

## Goal

Restructure both `claude-code-optimizations` and `wezterm` into a layout where:

- Each tool/optimization is a self-contained folder with its own README and setup notes.
- Cross-cutting tools live in their own sibling repos under `/mnt/d/labs/`, using the same internal shape as a single module.
- The event-sourcing meta-tooling (`CHANGELOG-SUMMARY.md`, `changelogs/`, `.changelog-status`, the workflow sections of `CLAUDE.md`, the `SETUP-GUIDE.md` event-sourcing prose) is removed; git history + per-folder READMEs carry its load.
- A machine can sync after `git pull` regardless of who ran the pull, using a machine-local git tag as the only persistent state.
- Modules declare their dependencies; the agent probes the machine and skips modules whose requirements don't match.

## Non-goals

- A multi-repo dependency manager, package registry, or version pinning. The repos are loose siblings; the agent walks each independently.
- An umbrella "tools index" repo. The "See also" pointer pattern in each baseline's top-level `setup.md` covers discovery.
- Backwards compatibility with `.changelog-status` files on existing machines. They become stale and ignored. A one-time fresh sync on each machine establishes the new `synced-on-<hostname>` tag.
- Preserving historical changelogs as files. Git history retains them on prior commits; `git show <commit>:changelogs/<file>.md` recovers them when needed.

## Design

### Topology

Five repos under `/mnt/d/labs/`:

| Repo | Role | Shape |
|---|---|---|
| `claude-code-optimizations` | Baseline (Claude Code config) | Top-level `setup.md` + module folders |
| `wezterm` | Baseline (WezTerm config) | Top-level `setup.md` + module folders |
| `claude-waiting-notification` | Cross-cutting (CC + WezTerm + Windows) | Single-module shape (flat files + `setup.md`) |
| `auto-screenshot` | Cross-cutting (CC + Windows; not WezTerm-dependent) | Single-module shape |
| `spawn-session` | Cross-cutting (CC + WezTerm) — already split | Already in this shape |

### Module shape

A module is a folder with three things:

```
<module>/
  README.md     human-facing intro: what this is, why it exists
  setup.md      free prose; agent reads and acts (Cat-1 — no enforced schema)
  <files>       flat layout — the actual scripts, configs, skill files, etc.
```

Cross-cutting repos use the same shape at the repo root — they *are* one module, so they have no top-level orchestration `setup.md` distinct from the module's own.

`setup.md` carries (by soft convention, not enforcement):

- A `**Requires:**` line near the top declaring dependencies (OS, terminal, installed apps). The agent uses this to skip modules whose requirements don't match the machine.
- A list of files in the module and where each one deploys on a machine.
- Per-machine values to substitute, marked with `<-- edit per machine: <what>` (existing convention preserved).
- Any post-deploy steps (chmod, register hook in settings.json, edit `.wezterm.lua`, etc.).

The skeleton converges by imitation — when the agent works on a module, it reads neighboring `setup.md`s and naturally writes new ones in the same shape. Modules that genuinely don't fit the skeleton (rare) get whatever shape they need.

### Top-level orchestration `setup.md` (baselines only)

Each baseline repo's top-level `setup.md` is the entrypoint when setting up a fresh machine. It contains:

- A one-line description of each module folder, with its `**Requires:**` summary.
- Ordering hints (e.g. `baseline-settings` should be installed before any module that registers a hook in `settings.json`).
- A "See also" section listing cross-cutting sibling repos with their roles and (placeholder) GitHub URLs:

  ```
  ## See also (cross-cutting tools)

  - claude-waiting-notification — Stop-hook + WezTerm Lua + Windows toast for idle CC sessions.
    <TBD: github URL once published>
  - auto-screenshot — Window-aware screen capture skill for Windows hosts.
    <TBD: github URL once published>
  - spawn-session — Fan a batch of independent tasks into N CC processes, each in its own WezTerm pane.
    <TBD: github URL once published>
  ```

  Both baselines list the cross-cutting repos that touch their domain. Some duplication is fine (e.g. `spawn-session` appears in both because it's relevant from both directions).

### Modules in `claude-code-optimizations` after restructure

Three modules:

- `baseline-settings/` — `settings.json` (slimmed: drops the bash-guardrails hook, the `check-cs-edit` hook, and the `agent-deck` Notification/PermissionRequest entries are out of scope and stay if currently in use).
- `statusline/` — `statusline-command.sh`.
- `claude-md/` — the global `~/.claude/CLAUDE.md` content.

### Modules in `wezterm` after restructure

One module per `[setup]` change in the current `CHANGELOG-SUMMARY.md`. Working list (final names finalized at migration time):

- `tab-nav-keybindings/`
- `vertical-scrollbar/`
- `default-cwd/`
- `tab-bar-style/`
- `ctrl-drag-window-move/`
- `smart-cd/`
- `pane-splitting/`
- `split-pane-cwd/` (consolidates the inheritance + robustness pair into one module)
- `tab-bar-font-size/` (may merge into `tab-bar-style/`; decided at migration)

### Cross-cutting repos — initial contents

Each list below is canonical — these are the exact paths to move at migration time.

- **`claude-waiting-notification/`** receives:
  - `config/hooks/notify-waiting.sh`
  - `config/windows-helpers/claude-waiting.lua`
  - `config/windows-helpers/wezterm-claude-notify.ps1`
  - `config/windows-helpers/preflight.ps1`
  - `changelogs/CHANGELOG-2026-04-16-claude-waiting-notification.md` (becomes the basis for the new repo's `setup.md`)
  - `docs/superpowers/specs/2026-04-15-claude-waiting-notification-design.md`
  - `docs/superpowers/plans/2026-04-16-claude-waiting-notification.md`
  - `AUDIT-PROMPT-notification-system.md` (root-level audit doc — applies to the notification system, moves with it)
- **`auto-screenshot/`** receives:
  - `config/skills/screenshot/` (entire folder: `SKILL.md`, `capture.ps1`, `tests/`)
  - `changelogs/CHANGELOG-2026-04-16-smart-screenshots.md` (basis for the new repo's `setup.md`)
  - `docs/superpowers/specs/2026-04-16-smart-screenshots-design.md`
  - `docs/superpowers/specs/2026-04-17-screenshot-v2-design.md`
  - `docs/superpowers/specs/2026-04-17-screenshot-v2-followups.md`
  - `docs/superpowers/plans/2026-04-16-smart-screenshots.md`
  - `docs/superpowers/plans/2026-04-17-screenshot-v2.md` (active v2 plan — the in-flight v2 work continues from here inside the new repo)
- **`spawn-session/`** — already exists; gains a `README.md` + module-style `setup.md` if not already present, no behavior change.

### `notify-waiting.sh` hook entries — owned by `claude-waiting-notification`

The current `settings.json` registers `notify-waiting.sh` on `Stop` (with arg `1`) and `UserPromptSubmit` (with arg `0`). Decision: those hook entries belong to the `claude-waiting-notification` install contract, not to `baseline-settings/`.

- **`baseline-settings/settings.json`** ships **without** the `notify-waiting.sh` entries. A machine that installs `baseline-settings` but skips `claude-waiting-notification` gets no dangling hook commands.
- **`claude-waiting-notification/setup.md`** instructs the agent (and documents for the user) to merge the two hook entries into `~/.claude/settings.json` at install time, alongside any other entries already there. Uninstall instructions remove them.

The pre-existing `agent-deck` entries on `Notification`, `PermissionRequest`, `PreCompact`, `SessionEnd`, `SessionStart`, `Stop`, `UserPromptSubmit` are out of scope for this reorg and stay in `baseline-settings/settings.json` as-is.

### What gets dropped

| Item | Reason |
|---|---|
| `pretooluse-bash-guardrails.py` (hook) | Agent does fine without it; the friction it adds outweighs its benefit. |
| `check-cs-edit.py` (hook) | C# inspectcode loop was over-engineered, never used on the work PC, agent produces good C# without it. |
| `rules/dotnet.md` | Tied to the same C# inspectcode workflow being dropped. |
| `scripts/parse-sarif.py` | Same workflow — parsed inspectcode SARIF for the agent. |
| `rules/python.md` | Trivial guidance the agent already follows. |
| `rules/frontend.md` | Same. |
| `CHANGELOG-SUMMARY.md`, `changelogs/`, `.changelog-status` | Replaced by per-module READMEs + git history. |
| `SETUP-GUIDE.md` (current contents) | Replaced by top-level `setup.md` orchestration. |
| Workflow sections of `CLAUDE.md` | Replaced by far slimmer `CLAUDE.md` describing the new layout and sync model. |
| `windows-helpers/` (folder) | Files redistribute into the cross-cutting `claude-waiting-notification` repo where they belong. |
| `AUDIT-PROMPT-notification-system.md` (root-level audit doc) | Already-applied artifact; git history preserves. |

### Sync model — `synced-on-<hostname>` movable git tag

Per-machine, per-repo, machine-local. Tags are not pushed by default — they stay on the local clone. The tag is the only persistent state.

**Algorithm when the user says "sync" / "update" the repo:**

1. Check for the tag: `git tag --list 'synced-on-<hostname>'`.
   - **Tag exists** → that's the previous sync point. Use it regardless of how many `git pull`s happened in between (the user pulling outside the agent is invisible — the tag still points at the last commit the agent actually applied).
   - **Tag missing** (fresh clone, lost tag, first run) → no baseline. Treat as fresh setup: the agent walks the top-level `setup.md`, presents the module menu, and the user picks.
2. Compute delta: `git log <tag>..HEAD --stat` shows what changed since last sync. Group by module folder. Present per module: "Module X has N new commits — review?"
3. Per module, walk the diff: `git diff <tag>..HEAD -- <module>/` with the agent's recommendation. User: yes / no / partial. Agent applies and adapts paths/values.
4. **Deletion case:** if a module folder was *removed* between `<tag>` and `HEAD`, the agent surfaces "Module X was removed upstream; remove from this machine?" rather than silently leaving stale files in `~/.claude/` or `C:\Users\<WIN_USER>\`.
5. On completion, advance the tag: `git tag -f synced-on-<hostname>` to point at the new HEAD. Advance regardless of whether modules were accepted or declined — declined modules don't get re-offered automatically (an explicit later "compare module X to my live config" is how to revisit).

**Edge cases:**

- User pulls in a separate shell, then asks the agent to sync: handled by step 1 — the tag is still where the last sync left it.
- Agent itself does the pull during sync: same flow; `git pull` happens before step 1, the tag's location is unchanged by the pull.
- User declines a module on one sync, wants to re-evaluate later: handled out-of-band — user asks the agent to "compare module X here to the repo," agent diffs `<module>/` against the live machine state and presents.

### Dependencies — declared per-module, probed per-machine

Each module's `setup.md` carries a `**Requires:**` line. Initial dependency assignments:

| Module / Repo | Requires |
|---|---|
| `baseline-settings` | Claude Code |
| `statusline` | Claude Code, bash |
| `claude-md` | Claude Code |
| `auto-screenshot` | Windows host, PowerShell 5+, WSL access to `powershell.exe`; Pester v5 for tests |
| `claude-waiting-notification` | WSL2, WezTerm on Windows 11, Claude Desktop installed (AUMID toast icon) |
| `spawn-session` | WezTerm, Claude Code, bash |
| WezTerm modules (each) | WezTerm |

The agent probes the machine at orchestration time (`uname`, `which wezterm`, `wsl.exe`, `powershell.exe`, etc.) and:

- Skips modules whose hard requirements are not met, with a one-line note ("skipping `claude-waiting-notification`: not on Windows / no WezTerm").
- Warns but offers anyway for soft mismatches (e.g., a module marked "WezTerm preferred" on a non-WezTerm machine).

The top-level `setup.md` table includes the `Requires` column so the user can see the matrix when picking modules.

### Per-machine values

Existing convention preserved unchanged. Each module's `setup.md` lists per-machine substitutions at the top:

```
## Per-machine values

- `<WSL_USER>` — your WSL username (appears in hook command paths in settings.json)
- `<WIN_USER>` — your Windows username (appears in toast script path)
- `<TIMEZONE>` — your TZ (appears in statusline-command.sh)
```

Files in the module use literal source-machine values with `<-- edit per machine: <what>` markers (or `// edit per machine: <what>` for JSON). Agent does the substitution at deploy time using the values the user provided.

## Migration

Migration is sequential, one repo at a time, on dedicated branches. Each step ends with a commit on `main` that leaves the repo in a working state (the new layout is functional even if some downstream consumers haven't been updated yet — they sync on their own schedule via the `synced-on-<hostname>` tag).

### Order

1. **`claude-code-optimizations` restructure.**
   - Cut `reorg/modular-layout` branch.
   - Create `baseline-settings/`, `statusline/`, `claude-md/` module folders. Move the relevant files in (`config/settings.json` → `baseline-settings/settings.json`, `config/statusline-command.sh` → `statusline/statusline-command.sh`, `config/CLAUDE.md` → `claude-md/CLAUDE.md`). Write each module's `README.md` + `setup.md`.
   - Slim `baseline-settings/settings.json`: drop the two `pretooluse-bash-guardrails.py` and `check-cs-edit.py` hook registrations, drop the two `notify-waiting.sh` hook registrations (those move to `claude-waiting-notification` in step 2). Keep the `agent-deck` entries as-is (out of scope).
   - Write the new top-level `setup.md` (orchestration menu + See also + ordering).
   - Write the new top-level `README.md` (curated index, public-facing).
   - Write the new (slim) top-level `CLAUDE.md` describing the new layout and the sync model.
   - Delete the following exact paths in this step:
     - `CHANGELOG-SUMMARY.md`, `SETUP-GUIDE.md`
     - `config/CLAUDE.md`, `config/settings.json`, `config/statusline-command.sh` (already moved into module folders above)
     - `config/rules/` (entire folder: `dotnet.md`, `python.md`, `frontend.md`)
     - `config/scripts/parse-sarif.py` (and `config/scripts/` if it becomes empty)
     - `config/hooks/pretooluse-bash-guardrails.py`, `config/hooks/check-cs-edit.py`
   - Defer to step 5: `changelogs/` (entire folder). The two cross-cutting changelogs inside it (`CHANGELOG-2026-04-16-claude-waiting-notification.md`, `CHANGELOG-2026-04-16-smart-screenshots.md`) are sources for the new repos' `setup.md` files in steps 2/3; deleting them in step 1 would orphan that source. See "Sequencing note" below.
   - **Intermediate state after this step:** `config/hooks/notify-waiting.sh`, `config/windows-helpers/`, `config/skills/screenshot/`, the screenshot/notification spec + plan docs in `docs/superpowers/`, and `AUDIT-PROMPT-notification-system.md` are still present. They leave the repo in steps 2 and 3.
   - Merge to main.

   **Sequencing note for `changelogs/` deletion:** the two cross-cutting changelogs (`CHANGELOG-2026-04-16-claude-waiting-notification.md`, `CHANGELOG-2026-04-16-smart-screenshots.md`) need to land in the cross-cutting repos before they're deleted from `claude-code-optimizations`. Two acceptable orderings: (a) copy them into the cross-cutting repos in this step 1 commit, then physically move them out in steps 2/3 (clean git history at the cost of a transient duplicate); or (b) defer the `changelogs/` deletion from step 1 to a final cleanup commit after step 3 lands. Prefer (b) — simpler, no transient duplication.
2. **Create `claude-waiting-notification/` repo.** Files to move (canonical list above in "Cross-cutting repos — initial contents"):
   - `git init` under `/mnt/d/labs/claude-waiting-notification/`.
   - Copy in: `config/hooks/notify-waiting.sh`, `config/windows-helpers/{claude-waiting.lua, wezterm-claude-notify.ps1, preflight.ps1}`, `changelogs/CHANGELOG-2026-04-16-claude-waiting-notification.md`, `docs/superpowers/specs/2026-04-15-claude-waiting-notification-design.md`, `docs/superpowers/plans/2026-04-16-claude-waiting-notification.md`, `AUDIT-PROMPT-notification-system.md`.
   - Reorganize inside the new repo: changelog content adapts into `setup.md`; design + plan docs land in `docs/specs/` and `docs/plans/` (or similar) for historical reference; audit prompt stays at root or moves to `docs/`.
   - Write `README.md` + finalized `setup.md` (the latter explains the file layout and includes the `notify-waiting.sh` `Stop`/`UserPromptSubmit` hook entries that need merging into `~/.claude/settings.json`).
   - Initial commit.
   - In `claude-code-optimizations`, delete the now-moved sources: `config/hooks/notify-waiting.sh`, `config/windows-helpers/` (entire folder), `docs/superpowers/specs/2026-04-15-claude-waiting-notification-design.md`, `docs/superpowers/plans/2026-04-16-claude-waiting-notification.md`, `AUDIT-PROMPT-notification-system.md`. The `changelogs/CHANGELOG-2026-04-16-claude-waiting-notification.md` deletion happens in the final cleanup commit (per step 1's sequencing note).
3. **Create `auto-screenshot/` repo.** Files to move (canonical list above):
   - `git init` under `/mnt/d/labs/auto-screenshot/`.
   - Copy in: `config/skills/screenshot/` (entire folder including `SKILL.md`, `capture.ps1`, `tests/`), `changelogs/CHANGELOG-2026-04-16-smart-screenshots.md`, `docs/superpowers/specs/{2026-04-16-smart-screenshots-design.md, 2026-04-17-screenshot-v2-design.md, 2026-04-17-screenshot-v2-followups.md}`, `docs/superpowers/plans/{2026-04-16-smart-screenshots.md, 2026-04-17-screenshot-v2.md}`.
   - Reorganize inside the new repo: changelog content adapts into `setup.md`; design + plan docs land in `docs/`; the active `2026-04-17-screenshot-v2.md` plan continues to drive in-flight v2 work from here.
   - Write `README.md` + finalized `setup.md` consolidating the design + plan + install steps. The skill is symlinked into `~/.claude/skills/screenshot/` (existing convention from the 2026-04-16 changelog).
   - Initial commit. The in-flight v2 work continues inside this repo from here.
   - In `claude-code-optimizations`, delete the now-moved sources: `config/skills/screenshot/` (entire folder), `docs/superpowers/specs/{2026-04-16-smart-screenshots-design.md, 2026-04-17-screenshot-v2-design.md, 2026-04-17-screenshot-v2-followups.md}`, `docs/superpowers/plans/{2026-04-16-smart-screenshots.md, 2026-04-17-screenshot-v2.md}`. The `changelogs/CHANGELOG-2026-04-16-smart-screenshots.md` deletion happens in the final cleanup commit.
4. **`wezterm` restructure** — same pattern as step 1, applied to `wezterm`. One module folder per `[setup]` changelog. Drop the meta. New top-level `setup.md` lists modules + See also.
5. **Final cleanup commit on `claude-code-optimizations`.** Delete:
   - `changelogs/` (entire folder — sources have already landed in their cross-cutting repos via steps 2/3).
   - `docs/superpowers/` (both `specs/` and `plans/` are emptied of pre-existing content by steps 2/3; the modular-reorg spec itself — this file — is the only remaining occupant and gets deleted here too, since git history preserves it on prior commits and the new layout doesn't carry historical specs forward).
   - `config/` (the now-empty directory — by this step every file inside has migrated out via step 1, step 2, or step 3). Confirm empty before deleting.
   Step 1's `setup.md` already references the new layout; nothing in the post-migration repo points back to `docs/superpowers/` or `config/`.
6. **Update placeholder GitHub URLs** — once the cross-cutting repos are pushed to GitHub, edit each baseline's top-level `setup.md` "See also" section to replace `<TBD: github URL once published>` with the real URLs.

### Migration verification (per repo)

After each step's main-branch merge:

- New layout exists; old meta files are gone.
- A fresh-machine simulation works: in a scratch checkout, run the agent against the new top-level `setup.md` and confirm it can walk the module menu without referencing the deleted meta.
- The first machine to sync (personal PC) creates its `synced-on-<hostname>` tag at the merge commit. From that tag forward, future commits flow through the new sync model.

### Existing-machine handling

The two existing machines (personal PC, work PC) are post-migration "fresh syncs":

- `.changelog-status` files become stale; the agent ignores them.
- On first sync after migration, `synced-on-<hostname>` tag is missing → fresh-setup flow → agent walks the module menu, machine confirms what's already installed, tag gets set at HEAD.
- Subsequent syncs use the standard delta flow.

## Open questions

- **`agent-deck` hooks in `settings.json`.** The current `settings.json` registers `agent-deck hook-handler` for several events (Notification, PermissionRequest, PreCompact, SessionEnd, SessionStart, Stop, UserPromptSubmit). These appear to be from a separate tool (`agent-deck`) and are unrelated to this reorg. Treat as out-of-scope: keep them in the slimmed `baseline-settings/settings.json` as-is. If the user later decides to drop them, that's a separate change.
- **`wezterm` module names finalized at migration.** The working list above is provisional. Some current changelogs may merge (e.g. the two split-pane CWD changes into one `split-pane-cwd/` module, the tab-bar font-size fix into `tab-bar-style/`).

## Verification

End state, validated on a single machine before propagating:

1. `claude-code-optimizations`: top-level layout is `README.md` + `setup.md` + `CLAUDE.md` + 3 module folders. No `changelogs/`, no `CHANGELOG-SUMMARY.md`, no `SETUP-GUIDE.md`, no `config/`.
2. `claude-waiting-notification`, `auto-screenshot`, `spawn-session` all exist as sibling repos under `/mnt/d/labs/`, each with `README.md` + `setup.md` + their files.
3. `wezterm`: top-level layout matches `claude-code-optimizations`. Each module folder is self-contained.
4. On the personal PC, running the agent on `claude-code-optimizations` with the new layout (a) sets `synced-on-<hostname>` at HEAD without claiming false work, (b) correctly identifies which modules are already installed in `~/.claude/`, (c) skips inapplicable modules.
5. Agent can read each module's `setup.md` in isolation and produce a working install — no implicit dependence on the deleted event-sourcing meta.
6. Cross-cutting repos' "See also" links resolve (after GitHub push and URL update); placeholders are clearly marked until then.

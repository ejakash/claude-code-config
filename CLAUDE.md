# CLAUDE.md — agent instructions for working in this repo

## What this repo is

Module-style configuration for Claude Code (`~/.claude/`). Each top-level folder is one self-contained module. Cross-cutting tools live in their own sibling repos under `/mnt/d/labs/` — see `setup.md` "See also."

## Module shape

Every module folder has:

```
<module>/
  README.md     human-facing intro
  setup.md      install instructions; agent reads + acts
  <files>       the actual config / scripts / skill files
```

`setup.md` is free prose. By soft convention each one carries a `**Requires:**` line (deps), a `## Per-machine values` section (substitution markers), a `## Files` section (where each file deploys), and `## Install` / `## Verify` steps.

## Sync model — `synced-on-<hostname>` git tag

Per-machine, per-repo, machine-local. Tags don't push by default.

When the user says "sync" or "update":

1. `git tag --list 'synced-on-$(hostname)'` — exists?
   - **Yes** → use as baseline, regardless of who ran the last `git pull`.
   - **No** → fresh-setup flow: walk `setup.md` module menu.
2. `git log <tag>..HEAD --stat` for the delta. Group by module folder. Walk per module.
3. Per module, `git diff <tag>..HEAD -- <module>/`. Recommend, ask user yes/no/partial, apply, adapt paths/values.
4. **Module deletion case:** if a module folder was removed upstream, surface "remove from this machine?" — do not silently leave stale files.
5. On completion, `git tag -f synced-on-$(hostname)` at HEAD. Advance even on partial accept; declined modules don't auto-re-offer.

Fallbacks if the tag is missing: `ORIG_HEAD` after a fresh pull, `git reflog`, or ask the user "what's the last commit you synced?"

## Per-machine values

Files in modules use literal source-machine values (e.g. `pudge`, `spirit`, `America/Chicago`) with `<-- edit per machine: <what>` markers (or `// edit per machine: <what>` in JSON). The agent substitutes at deploy time.

## Adding a new module

1. Create `<new-module>/` folder.
2. Add `README.md` + `setup.md` (use neighbors as a template — Cat-1 free prose).
3. Drop files in.
4. Update top-level `setup.md` module table.
5. Commit. Other machines pick it up on next sync.

## Removing a module

Just `git rm -r <module>/`. The sync model handles cleanup on other machines (step 4 of sync above).

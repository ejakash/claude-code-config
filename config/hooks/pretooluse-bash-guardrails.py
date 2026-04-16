#!/usr/bin/env python3
"""
PreToolUse hook: enforce good Bash habits in Claude Code.
- Rewrites: cd <path> && git <args>  ->  git -C "<path>" <args>
- Denies: cat/grep/find/xargs (use Read/Grep/Glob instead)
- Denies: python -c one-liners (use Edit/Grep/Glob instead)
"""

import json
import re
import sys


def main():
    try:
        raw = sys.stdin.read()
        if not raw.strip():
            sys.exit(0)
        evt = json.loads(raw)
    except Exception:
        sys.exit(0)

    if evt.get("tool_name") != "Bash":
        sys.exit(0)

    cmd = evt.get("tool_input", {}).get("command", "")
    if not cmd.strip():
        sys.exit(0)

    cmd_trim = cmd.strip()

    # 1) Rewrite "cd <path> && git <args>" -> "git -C <path> <args>"
    m = re.match(r'^\s*cd\s+(.+?)\s*&&\s*git\s+(.+)$', cmd_trim)
    if m:
        path = m.group(1).strip().strip('"').strip("'")
        git_args = m.group(2).strip()
        new_cmd = f'git -C "{path}" {git_args}'
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "permissionDecisionReason": "Rewrote compound cd+git into git -C to avoid compound statement confirmation.",
                "updatedInput": {"command": new_cmd},
                "additionalContext": "Avoid cd && git compounds. Use git -C <path> for repo-specific operations.",
            }
        }))
        sys.exit(0)

    # 2) Deny bash commands that duplicate built-in tools
    tool_alternatives = [
        (r'^\s*cat\s+',                   "Use the Read tool instead of cat."),
        (r'^\s*(grep|egrep|fgrep|rg)\s+', "Use the Grep tool instead of grep/rg."),
        (r'^\s*find\s+',                  "Use the Glob tool instead of find."),
        (r'^\s*xargs\s+',                 "Use Grep/Glob with appropriate patterns instead of xargs pipelines."),
    ]
    for pattern, message in tool_alternatives:
        if re.match(pattern, cmd_trim):
            print(json.dumps({
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": message,
                    "additionalContext": "Claude Code has built-in tools (Read, Grep, Glob, Edit) that work without Bash permissions. Use them.",
                }
            }))
            sys.exit(0)

    # 3) Deny python -c one-liners
    if re.match(r'^\s*(python3?)\s+-c\s+', cmd_trim):
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": "Do not use python -c for file operations. Use Edit (with replace_all), Grep, and Glob instead.",
                "additionalContext": "If you need to run Python code, write it to a file first. Never use python -c for find-and-replace or file manipulation.",
            }
        }))
        sys.exit(0)

    # Default: allow normally
    sys.exit(0)


if __name__ == "__main__":
    main()

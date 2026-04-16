#!/usr/bin/env python3
"""
PostToolUse hook: when a .cs file is edited, remind Claude to run inspectcode.
"""
import json
import sys


def main():
    data = json.load(sys.stdin)
    file_path = (
        data.get("tool_response", {}).get("filePath", "")
        or data.get("tool_input", {}).get("file_path", "")
    )

    if not file_path.endswith(".cs"):
        return
    if any(seg in file_path.replace("\\", "/") for seg in ("/obj/", "/bin/")):
        return

    name = file_path.replace("\\", "/").split("/")[-1]
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": (
                f"[inspectcode] {name} changed. Consider running: "
                f"jb inspectcode -o=inspect-results.json -f=Sarif -e=WARNING "
                f"--no-build --include=\"**/{name}\" <solution-file> "
                f"then parse with: python3 ~/.claude/scripts/parse-sarif.py inspect-results.json --min-level warning"
            ),
        }
    }))


if __name__ == "__main__":
    main()

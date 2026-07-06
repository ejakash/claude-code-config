#!/usr/bin/env python3
"""
parse-sarif.py — Extract and display issues from a JetBrains inspectcode SARIF output file.

Usage:
    python parse-sarif.py <sarif-file> [--min-level warning|error|note]

Output:
    Prints one line per issue: [LEVEL] file:line — message
    Exits with code 1 if any issues are found, 0 if clean.

Filters:
    - Skips results in generated files: obj/, bin/, *.g.cs, *.AssemblyInfo.cs
    - Default minimum level: note (shows everything); use --min-level to narrow down

Examples:
    python parse-sarif.py inspect-results.json
    python parse-sarif.py inspect-results.json --min-level warning
"""

import json
import sys
import argparse
import os
import re

LEVEL_ORDER = {"note": 0, "warning": 1, "error": 2}

GENERATED_PATTERNS = [
    re.compile(r"[\\/]obj[\\/]"),
    re.compile(r"[\\/]bin[\\/]"),
    re.compile(r"\.g\.cs$"),
    re.compile(r"\.AssemblyInfo\.cs$"),
    re.compile(r"GeneratedMSBuildEditorConfig\.editorconfig$"),
    re.compile(r"Microsoft\.NET\.Test\.Sdk\.Program\.cs$"),
]


def is_generated(uri: str) -> bool:
    return any(p.search(uri) for p in GENERATED_PATTERNS)


def parse_sarif(path: str, min_level: str) -> list[dict]:
    min_order = LEVEL_ORDER.get(min_level.lower(), 0)

    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    issues = []
    for run in data.get("runs", []):
        # Build a rule-id -> default level map from the run's rules
        rule_levels: dict[str, str] = {}
        tool_rules = (
            run.get("tool", {})
               .get("driver", {})
               .get("rules", [])
        )
        for rule in tool_rules:
            rid = rule.get("id", "")
            default_level = (
                rule.get("defaultConfiguration", {}).get("level", "warning")
            )
            rule_levels[rid] = default_level

        for result in run.get("results", []):
            level = result.get("level") or rule_levels.get(result.get("ruleId", ""), "warning")
            if LEVEL_ORDER.get(level, 0) < min_order:
                continue

            msg = result.get("message", {}).get("text", "").strip()
            rule_id = result.get("ruleId", "")

            locs = result.get("locations", [])
            uri = ""
            line = ""
            if locs:
                pl = locs[0].get("physicalLocation", {})
                uri = pl.get("artifactLocation", {}).get("uri", "")
                line = pl.get("region", {}).get("startLine", "")

            if is_generated(uri):
                continue

            issues.append({
                "level": level.upper(),
                "uri": uri,
                "line": line,
                "rule_id": rule_id,
                "message": msg,
            })

    return issues


def main():
    parser = argparse.ArgumentParser(description="Parse JetBrains inspectcode SARIF results.")
    parser.add_argument("sarif_file", help="Path to the SARIF JSON file")
    parser.add_argument(
        "--min-level",
        default="note",
        choices=["note", "warning", "error"],
        help="Minimum severity level to report (default: note)",
    )
    args = parser.parse_args()

    if not os.path.exists(args.sarif_file):
        print(f"ERROR: File not found: {args.sarif_file}", file=sys.stderr)
        sys.exit(2)

    issues = parse_sarif(args.sarif_file, args.min_level)

    if not issues:
        print("No issues found.")
        sys.exit(0)

    for issue in issues:
        loc = f"{issue['uri']}:{issue['line']}" if issue["line"] else issue["uri"]
        rule = f" ({issue['rule_id']})" if issue["rule_id"] else ""
        print(f"[{issue['level']}] {loc}{rule} — {issue['message']}")

    print(f"\n{len(issues)} issue(s) found.")
    sys.exit(1)


if __name__ == "__main__":
    main()

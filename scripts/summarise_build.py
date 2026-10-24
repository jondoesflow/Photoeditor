#!/usr/bin/env python3
"""Pulls compiler errors, warnings and test failures out of an xcodebuild log into Markdown."""
import re
import sys
from pathlib import Path

log = Path(sys.argv[1]).read_text(errors="replace") if Path(sys.argv[1]).exists() else ""
out = Path(sys.argv[2])

diag = re.compile(r"^([/@][^:\n]+):(\d+):(\d+): (error|warning): (.+)$", re.M)
seen = set()
errors, warnings = [], []
for path, line, col, kind, message in diag.findall(log):
    key = (path, line, kind, message)
    if key in seen:
        continue
    seen.add(key)
    short = re.sub(r"^.*?/(Grade|GradeTests|GradeUITests)/", r"\1/", path)
    (errors if kind == "error" else warnings).append(f"- `{short}:{line}:{col}` {message}")

other_warnings = sorted({m for m in re.findall(r"^warning: (.+)$", log, re.M)})
test_failures = sorted(set(re.findall(r"^.*(?:error: -\[|✘ |Test .* failed|Issue recorded).*$", log, re.M)))[:200]
result = re.findall(r"\*\* (TEST SUCCEEDED|TEST FAILED|BUILD SUCCEEDED|BUILD FAILED|TEST BUILD FAILED) \*\*", log)

lines = [
    "# Build summary",
    "",
    f"Result: {result[-1] if result else 'unknown'}",
    "",
    f"## Errors ({len(errors)})", *errors, "",
    f"## Warnings ({len(warnings)})", *warnings, "",
    f"## Other warnings ({len(other_warnings)})", *[f"- {w}" for w in other_warnings], "",
    f"## Test failures ({len(test_failures)})", *[f"- {t.strip()}" for t in test_failures],
]
out.write_text("\n".join(lines) + "\n")
print("\n".join(lines[:6]))

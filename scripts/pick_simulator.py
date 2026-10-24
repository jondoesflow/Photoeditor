#!/usr/bin/env python3
"""Reads `xcrun simctl list devices available -j` on stdin and prints the UDID of the
newest non-Max iPhone Pro on the newest iOS runtime (then its name and runtime)."""
import json
import re
import sys

devices = json.load(sys.stdin)["devices"]
best = None
for runtime, sims in devices.items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for sim in sims:
        name = sim.get("name", "")
        if not sim.get("isAvailable", True) or not name.startswith("iPhone"):
            continue
        preference = 2 if ("Pro" in name and "Max" not in name) else 1
        number = int((re.search(r"iPhone (\d+)", name) or [0, 0])[1] or 0)
        key = (version, preference, number, name)
        if best is None or key > best[0]:
            best = (key, sim["udid"], name, runtime)

if best is None:
    sys.exit("No iPhone simulator available")
print(best[1])
print(best[2])
print(best[3])

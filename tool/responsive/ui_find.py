#!/usr/bin/env python3
"""Read a `uiautomator dump` XML on stdin; print the center "x y" (px) of the
first clickable node whose content-desc (or text) matches the regex argv[1].
Prints nothing when not found. Used by shoot_device.sh / perf_device.sh."""
import re
import sys
import xml.etree.ElementTree as ET

pat = re.compile(sys.argv[1])
try:
    root = ET.fromstring(sys.stdin.read())
except ET.ParseError:
    sys.exit(0)
best = None
for n in root.iter("node"):
    desc = n.get("content-desc") or n.get("text") or ""
    if not desc or not pat.search(desc):
        continue
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds", ""))
    if not m:
        continue
    x1, y1, x2, y2 = map(int, m.groups())
    if x2 <= x1 or y2 <= y1:
        continue
    cand = ((x1 + x2) // 2, (y1 + y2) // 2)
    if n.get("clickable") == "true":
        best = cand
        break
    best = best or cand
if best:
    print(f"{best[0]} {best[1]}")

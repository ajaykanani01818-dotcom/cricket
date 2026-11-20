#!/usr/bin/env python3
"""Summarise SurfaceFlinger timestats + gfxinfo dumps (see perf_device.sh).
usage: perf_parse.py <package> <timestats.txt> <gfxinfo.txt> <build> <swipes>"""
import re
import sys

pkg, ts_path, gfx_path, build, swipes = sys.argv[1:6]
ts = open(ts_path, errors="replace").read()
gfx = open(gfx_path, errors="replace").read()

refresh = re.search(r"displayRefreshRate = (\d+)", ts)
period = 1000.0 / int(refresh.group(1)) if refresh else 16.67

best = None
for block in ts.split("layerName = ")[1:]:
    name = block.split("\n", 1)[0]
    if pkg not in name or "SurfaceView" not in name:
        continue
    total = int(re.search(r"totalFrames = (\d+)", block).group(1))
    if best is None or total > best[1]:
        best = (name, total, block)

print(f"package: {pkg} ({build} build), swipes: {swipes} up + {swipes} down, refresh {1000 / period:.0f} Hz")
if best:
    name, total, block = best
    hist_line = block.split("present2present histogram is as below:\n", 1)[1].split("\n", 1)[0]
    hist = {int(k[:-2]): int(v) for k, v in (kv.split("=") for kv in hist_line.split())}
    active = {k: v for k, v in hist.items() if k <= 150}  # drop idle gaps
    n = sum(active.values())
    janky = sum(v for k, v in active.items() if k >= 1.5 * period)
    severe = sum(v for k, v in active.items() if k >= 4 * period)
    fps = re.search(r"averageFPS = ([\d.]+)", block)
    dropped = re.search(r"droppedFrames = (\d+)", block)
    print(f"Flutter SurfaceView layer: {name}")
    print(f"  frames presented: {total}, averageFPS: {fps.group(1) if fps else '?'}, dropped: {dropped.group(1) if dropped else '?'}")
    print(f"  JANK: {janky}/{n} frames = {100.0 * janky / max(n, 1):.1f}% (>= {1.5 * period:.0f} ms), "
          f"severe (>= {4 * period:.0f} ms): {severe}")
    print("  present-to-present histogram (non-zero): " + " ".join(f"{k}ms={v}" for k, v in sorted(hist.items()) if v))
else:
    print("no SurfaceView layer for the package in timestats (app not in foreground?)")

g_total = re.search(r"Total frames rendered: (\d+)", gfx)
g_jank = re.search(r"Janky frames: (\d+) \(([\d.]+)%\)", gfx)
pct = {p: re.search(rf"^{p}th percentile: (\d+)ms", gfx, re.M) for p in (50, 90, 95, 99)}
print(f"gfxinfo (hwui, Android views only): frames {g_total.group(1) if g_total else '?'}, "
      f"janky {g_jank.group(1) + ' (' + g_jank.group(2) + '%)' if g_jank else '?'}, "
      + ", ".join(f"p{p} {m.group(1)}ms" for p, m in pct.items() if m))

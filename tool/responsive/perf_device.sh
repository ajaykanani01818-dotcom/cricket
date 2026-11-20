#!/usr/bin/env bash
# Scroll-jank baseline for the INSTALLED app on a real Android device (never installs).
#
#   tool/responsive/perf_device.sh -s 192.168.1.2:41185                 # com.cricticker.app.dev
#   tool/responsive/perf_device.sh -s <id> --package com.cricticker.app --swipes 15
#
# Launches the app, waits for the Live (home) list, then swipes the list up and
# down and reports:
#  - SurfaceFlinger timestats for the Flutter SurfaceView layer (the real
#    numbers for Flutter: present-to-present histogram -> FPS + jank %, where a
#    janky frame is one presented >= 1.5 refresh periods after the previous
#    one, excluding idle gaps > 150 ms);
#  - `dumpsys gfxinfo <pkg> framestats` summary. NOTE: Flutter draws into its own
#    SurfaceView, so hwui gfxinfo normally shows 0 frames for Flutter content;
#    it is kept for comparison with the old RN app / platform views.
# Measure a --profile or --release build: debug builds (kernel_blob.bin, JIT)
# are many times slower and not representative.
set -euo pipefail
DEVICE=""; PKG="com.cricticker.app.dev"; SWIPES=10; OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--device) DEVICE="$2"; shift 2 ;;
    --package) PKG="$2"; shift 2 ;;
    --swipes) SWIPES="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
done
[[ -n "$DEVICE" ]] || { echo "usage: $0 -s <adb device id> [--package pkg] [--swipes N]" >&2; exit 2; }
ADB=(adb -s "$DEVICE")
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${OUT:-${SHOTS_DIR:-$HERE/../../build/device_perf}/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"

APK="$("${ADB[@]}" shell pm path "$PKG" | head -1 | sed 's/^package://' | tr -d '\r')"
[[ -n "$APK" ]] || { echo "$PKG is not installed on $DEVICE" >&2; exit 1; }
if "${ADB[@]}" shell "unzip -l '$APK' 2>/dev/null | grep -q kernel_blob.bin"; then
  echo "WARNING: $PKG is a DEBUG (JIT) build - numbers are not representative; use flutter install --profile"
  BUILD=debug
else
  BUILD=aot
fi

cleanup() { "${ADB[@]}" shell dumpsys SurfaceFlinger --timestats -disable >/dev/null 2>&1 || true; }
trap cleanup EXIT

read -r W H < <("${ADB[@]}" shell wm size | tail -1 | grep -o '[0-9]*x[0-9]*' | tr x ' ')
X=$((W / 2)); Y1=$((H * 70 / 100)); Y2=$((H * 30 / 100))

"${ADB[@]}" shell am force-stop "$PKG"
"${ADB[@]}" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 10 # splash + first data

"${ADB[@]}" shell dumpsys gfxinfo "$PKG" reset >/dev/null
"${ADB[@]}" shell dumpsys SurfaceFlinger --timestats -enable -clear >/dev/null
for _ in $(seq "$SWIPES"); do "${ADB[@]}" shell input swipe "$X" "$Y1" "$X" "$Y2" 250; sleep 0.5; done
for _ in $(seq "$SWIPES"); do "${ADB[@]}" shell input swipe "$X" "$Y2" "$X" "$Y1" 250; sleep 0.5; done
"${ADB[@]}" shell dumpsys SurfaceFlinger --timestats -dump > "$OUT/timestats.txt"
"${ADB[@]}" shell dumpsys gfxinfo "$PKG" framestats > "$OUT/gfxinfo.txt"

python3 "$HERE/perf_parse.py" "$PKG" "$OUT/timestats.txt" "$OUT/gfxinfo.txt" "$BUILD" "$SWIPES" | tee "$OUT/summary.txt"
echo "$OUT"

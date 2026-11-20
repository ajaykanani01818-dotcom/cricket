#!/usr/bin/env bash
# Screenshot the INSTALLED app on a real Android device over adb, walking the
# bottom tabs (+ the first match detail), optionally at simulated screen sizes.
# It never installs anything; install first with e.g. `flutter run -d <id>`
# or `flutter install -d <id>`.
#
#   tool/responsive/shoot_device.sh -s 192.168.1.2:41185
#   tool/responsive/shoot_device.sh -s 192.168.1.2:41185 --sizes "native 720x1600@320 1440x3200@640"
#   tool/responsive/shoot_device.sh -s <id> --package com.cricticker.app --out /tmp/shots
#
# --sizes: space separated list of "native" or WxH@DENSITY (physical px @ dpi).
#   720x1600@360  -> small phone (320x711 dp)     720x1600@320  -> 360x800 dp phone
#   1080x2408@420 -> large phone (411x917 dp)     1600x2560@320 -> tablet-ish (800x1280 dp)
# realme/ColorOS (and MIUI) refuse `wm size` unless Developer options >
# "Disable permission monitoring" is on; such sizes are skipped with a hint.
# `wm size` / `wm density` overrides are ALWAYS reset on exit (trap), even on
# Ctrl-C or errors. Tabs are located via `uiautomator dump` (Flutter semantics
# labels "Live", "Matches", ...), falling back to the tab bar geometry.
set -euo pipefail

DEVICE=""
PKG="com.cricticker.app.dev"
SIZES="native"
OUT=""
WAIT="${WAIT:-4}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--device) DEVICE="$2"; shift 2 ;;
    --package) PKG="$2"; shift 2 ;;
    --sizes) SIZES="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
done
[[ -n "$DEVICE" ]] || { echo "usage: $0 -s <adb device id> [--sizes ...] [--package ...] [--out dir]" >&2; exit 2; }
ADB=(adb -s "$DEVICE")
OUT="${OUT:-${SHOTS_DIR:-$(cd "$(dirname "$0")/../.." && pwd)/build/device_shots}/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"
HERE="$(cd "$(dirname "$0")" && pwd)"

"${ADB[@]}" shell pm path "$PKG" >/dev/null 2>&1 || { echo "$PKG is not installed on $DEVICE" >&2; exit 1; }

reset_wm() {
  "${ADB[@]}" shell wm size reset >/dev/null 2>&1 || true
  "${ADB[@]}" shell wm density reset >/dev/null 2>&1 || true
}
trap 'reset_wm; echo "wm size/density reset"' EXIT
trap 'exit 130' INT TERM

shot() { "${ADB[@]}" exec-out screencap -p > "$OUT/$1.png"; echo "  $1.png"; }

# Prints "x y" (px) of the node whose content-desc matches $1 (regex), or nothing.
find_node() {
  "${ADB[@]}" shell uiautomator dump /sdcard/cbx_ui.xml >/dev/null 2>&1 || return 0
  "${ADB[@]}" exec-out cat /sdcard/cbx_ui.xml | python3 "$HERE/ui_find.py" "$1"
}

tap_tab() { # index name
  local xy
  xy="$(find_node "^$2\$")"
  if [[ -z "$xy" ]]; then
    # Fallback: floating tab bar (16dp side margin, 60dp tall, ~20dp + nav bar from bottom).
    local wh dens
    wh="$("${ADB[@]}" shell wm size | tail -1 | grep -o '[0-9]*x[0-9]*')"
    dens="$("${ADB[@]}" shell wm density | tail -1 | grep -o '[0-9]*$')"
    xy="$(python3 -c "w,h=map(int,'$wh'.split('x'));d=$dens/160;i=$1;print(int((16+(w/d-32)/6*(i+.5))*d), int(h-(48+50)*d))")"
  fi
  "${ADB[@]}" shell input tap $xy
}

# The in-app rating prompt ("Enjoying CrickBex?") can pop up mid-walk: dismiss it.
dismiss_prompt() {
  local xy
  xy="$(find_node '^Maybe later$')"
  if [[ -n "$xy" ]]; then "${ADB[@]}" shell input tap $xy; sleep 1; echo "  (dismissed rating prompt)"; fi
}

TABS=(Live Matches Series Ranking Players Settings)
for size in $SIZES; do
  reset_wm
  label="native"
  if [[ "$size" != native ]]; then
    if ! "${ADB[@]}" shell wm size "${size%@*}" >/dev/null 2>&1 || ! "${ADB[@]}" shell wm density "${size#*@}" >/dev/null 2>&1; then
      echo "SKIP $size: 'wm size/density' was refused (SecurityException). On realme/ColorOS/MIUI enable" >&2
      echo "  Developer options > 'Disable permission monitoring' (or 'USB debugging (Security settings)'), then retry." >&2
      reset_wm
      continue
    fi
    label="${size/@/_dpi}"
  fi
  echo "== $label ($("${ADB[@]}" shell wm size | tail -1 | tr -d '\r'), $("${ADB[@]}" shell wm density | tail -1 | tr -d '\r'))"
  "${ADB[@]}" shell am force-stop "$PKG"
  "${ADB[@]}" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep $((WAIT + 4)) # splash + first data
  for i in "${!TABS[@]}"; do
    tap_tab "$i" "${TABS[$i]}"
    sleep "$WAIT"
    dismiss_prompt
    shot "${label}_$(echo "${TABS[$i]}" | tr '[:upper:]' '[:lower:]')"
  done
  # First match card on the Live tab -> match detail.
  tap_tab 0 Live; sleep 2
  xy="$(find_node ' vs ')"
  if [[ -n "$xy" ]]; then
    "${ADB[@]}" shell input tap $xy; sleep "$WAIT"; dismiss_prompt; shot "${label}_match_detail"
    "${ADB[@]}" shell input keyevent KEYCODE_BACK
  else
    echo "  (no match card found)"
  fi
done
echo "$OUT"

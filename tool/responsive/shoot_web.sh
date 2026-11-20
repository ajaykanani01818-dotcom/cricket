#!/usr/bin/env bash
# Build the Flutter web app once, serve it, and capture the responsive
# screenshot matrix (or perf timings) with Playwright + Google Chrome.
#
#   tool/responsive/shoot_web.sh                       # release build, all viewports x dpr 1,2,3
#   tool/responsive/shoot_web.sh --dpr 1 --scrolls 1   # quicker, plus one scrolled frame per route
#   tool/responsive/shoot_web.sh --no-build --viewports 320x640,1440x900 --routes home,matches
#   tool/responsive/shoot_web.sh --profile             # profile build + --perf timings
#   tool/responsive/shoot_web.sh --profile --cpu-throttle 4
#
# Env: ENV_FILE (default env/local.json), PORT (8099), SHOTS_DIR (output root,
# default build/responsive_shots; a timestamped folder is created inside),
# WEBAPP_TESTING (path to with_server.py; optional, falls back to a built-in server).
# Every other flag is passed to tool/responsive/shoot_web.py (see --help there).
set -euo pipefail
export PYTHONUNBUFFERED=1
cd "$(dirname "$0")/../.."

ENV_FILE="${ENV_FILE:-env/local.json}"
PORT="${PORT:-8099}"
BUILD=1
MODE=release
PASS=()
for a in "$@"; do
  case "$a" in
    --no-build) BUILD=0 ;;
    --profile) MODE=profile ;;
    *) PASS+=("$a") ;;
  esac
done

if [[ "$MODE" == profile ]]; then
  DIR=build/web_profile
  PASS+=(--perf)
else
  DIR=build/web
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "missing $ENV_FILE (copy env/local.example.json and fill API_BASE_URL/API_SECRET)" >&2
  exit 1
fi

if [[ "$BUILD" == 1 ]]; then
  echo "== flutter build web --$MODE -> $DIR"
  OUTARG=()
  # Only pass --output for the non-default dir: `--output build/web` makes
  # flutter wipe its own output (fonts/assets go missing).
  [[ "$DIR" != build/web ]] && OUTARG=(--output "$PWD/$DIR")
  # Clean output: an incremental build does not restore deleted asset files.
  rm -rf "$DIR"
  flutter build web "--$MODE" --dart-define-from-file="$ENV_FILE" --no-wasm-dry-run ${OUTARG[@]+"${OUTARG[@]}"}
fi
[[ -f "$DIR/index.html" ]] || { echo "no build in $DIR (drop --no-build)" >&2; exit 1; }

WT="${WEBAPP_TESTING:-$(cd .. && pwd)/.claude/skills/webapp-testing/scripts/with_server.py}"
if [[ -f "$WT" ]]; then
  exec python3 "$WT" --server "python3 -m http.server $PORT --bind 127.0.0.1 -d $DIR" --port "$PORT" -- \
    python3 tool/responsive/shoot_web.py --url "http://localhost:$PORT" ${PASS[@]+"${PASS[@]}"}
else
  exec python3 tool/responsive/shoot_web.py --serve "$DIR" --port "$PORT" ${PASS[@]+"${PASS[@]}"}
fi

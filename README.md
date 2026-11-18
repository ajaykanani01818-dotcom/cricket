# CrickBex — Flutter

Flutter port of `../crickbex-app` (React Native/Expo). Uses ONLY the local
`livescore-postdata` API (no production fallback).

## Run
1. Start `LiveScore/livescore-scrap` (scraper) and `LiveScore/livescore-postdata` (API, port 8001).
2. `cp env/local.example.json env/local.json` and fill `API_BASE_URL`
   (`http://<mac-lan-ip>:8001/api/cricbex`) + `API_KEY` (postdata `SB_LIVE_SCORE_API_KEY`).
3. `flutter run --dart-define-from-file=env/local.json` (debug package: `com.crickbex.dark.dev`).

## Tests
- Unit + widget (no device): `flutter test`  (423 tests)
- End-to-end on a device against the local API:
  `flutter test integration_test/app_e2e_test.dart -d DEVICE_ID --dart-define-from-file=env/local.json`
- Frame timings (profile mode) → `build/perf/*.timeline_summary.json`:
  `flutter drive --profile --no-dds --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart --dart-define-from-file=env/local.json -d DEVICE_ID`
  (`--dart-define=PERF_DIAG=true` adds per-widget build events; `--dart-define=PRELOAD_TABS=true` to experiment with tab preloading.)
- Stress: `adb shell monkey -p com.crickbex.dark.dev --throttle 120 --pct-syskeys 2 --pct-appswitch 0 -v 5000`

## Structure
`lib/core` (theme, API client/cache, services, transforms, router/shell, shared widgets),
`lib/features/<feature>`; porting rules in `PORTING_GUIDE.md`.

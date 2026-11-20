# Cric Ticker — Flutter

Live cricket scores, commentary, scorecards, fixtures, series, rankings and
players. Flutter app (Android + iOS; web build for responsive checks), ported
from an earlier React Native app. Data comes ONLY from the project's own
`livescore-postdata` API (no production fallback).

| | |
|---|---|
| App name | Cric Ticker (`lib/core/brand/brand.dart` is the only place for brand strings) |
| Android applicationId | `com.cricticker.app` (release), `com.cricticker.app.dev` (debug/profile) |
| iOS bundle id | `com.cricticker.app` |
| Dart package | `crickbex` (internal import name only, never shown to users) |

## Run
1. Start `LiveScore/livescore-scrap` (scraper) and `LiveScore/livescore-postdata` (API, port 8001).
2. `cp env/local.example.json env/local.json` and fill `API_BASE_URL` and `API_SECRET`.
3. `flutter run --dart-define-from-file=env/local.json` (debug package: `com.cricticker.app.dev`).

## Navigation
Fixed bottom bar with five tabs, in this order (`lib/core/router/app_router.dart`):

| Tab | Route | Pushed from it |
|---|---|---|
| Home | `/home` | search, match / player / series detail |
| Live | `/live` | match detail |
| Matches | `/matches` | match detail |
| Discover | `/discover` | `/discover/series`, `/discover/rankings`, `/discover/players` |
| Settings | `/settings` | `privacy`, `terms`, `contact` (help and support), `about`, `app-info`, `more` (legacy) |

Every tab root also has `match/:matchId`, `player/:playerKey`,
`series-detail/:seriesId` and the info pages, so details push on the current
tab's stack (`AppNav.match/player/seriesDetail/page`). Old paths `/series`,
`/ranking`, `/players` redirect into Discover. There is no onboarding: the
native splash goes straight to Home.

## Settings, legal and contact
- Appearance: System (default), Light, Dark; applied instantly and persisted.
- Support: ajaykanani01818@gmail.com (feedback subject "Cric Ticker Feedback").
- Privacy policy and terms of use are rendered in the app with the same wording
  as the hosted pages, plus an "Open on web" link:
  - Website: https://ajaykanani01818-dotcom.github.io/cricket/
  - Privacy policy: https://ajaykanani01818-dotcom.github.io/cricket/privacy-policy.html
  - Terms of use: https://ajaykanani01818-dotcom.github.io/cricket/terms.html
  - Support: https://ajaykanani01818-dotcom.github.io/cricket/support.html
- The hosted pages' source is `../legal-site/`. The bundled copy is
  `lib/features/settings/legal_documents.dart` (the `<main>` of each page,
  verbatim); `test/settings/legal_documents_test.dart` fails when they drift.
  After editing a hosted page, copy its `<main>` into that file.
- Rating: no custom rating dialog and no sentiment gating. The system review
  sheet (`in_app_review` `requestReview()`) is requested only after a positive
  moment, from the 3rd session on, after at least 3 match views, at most once
  per 30 days and once per run, never on back or exit
  (`lib/features/review/`). Settings has an always-visible "Rate Cric Ticker"
  row that opens the store listing.

## Tests
- Unit + widget (no device): `flutter test`
- End-to-end on a device against the local API:
  `flutter test integration_test/app_e2e_test.dart -d DEVICE_ID --dart-define-from-file=env/local.json`
- Frame timings (profile mode) → `build/perf/*.timeline_summary.json`:
  `flutter drive --profile --no-dds --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart --dart-define-from-file=env/local.json -d DEVICE_ID`
  (`--dart-define=PERF_DIAG=true` adds per-widget build events; `--dart-define=PRELOAD_TABS=true` to experiment with tab preloading.)
- Stress: `adb shell monkey -p com.cricticker.app.dev --throttle 120 --pct-syskeys 2 --pct-appswitch 0 -v 5000`

## Testing in Chrome & on devices
Scripts live in `tool/responsive/`. The browser calls the API cross-origin
(`API_BASE_URL` from `env/local.json`); livescore-postdata's `cors()` already
allows it. Ads (google_mobile_ads) and in-app review are disabled on web.

**Chrome (interactive)**
```sh
flutter run -d chrome --dart-define-from-file=env/local.json
flutter build web --dart-define-from-file=env/local.json        # -> build/web
python3 -m http.server 8099 -d build/web                        # open http://localhost:8099/#/live
```
Routes use hash URLs: `#/home`, `#/live`, `#/matches`, `#/discover`,
`#/discover/series`, `#/discover/rankings`, `#/discover/players`, `#/settings`,
`#/settings/privacy`, `#/settings/terms`, `#/live/match/<matchId>`. Detail pages opened by tapping keep the
URL unchanged (go_router `push`). Note: a web build embeds `API_SECRET` in
`main.dart.js` — serve it locally only.

**Responsive screenshots in Chrome** (Python Playwright + installed Google Chrome;
`python3 -m playwright install chromium` if Chrome is missing)
```sh
tool/responsive/shoot_web.sh                         # build + 8 viewports x DPR 1,2,3 x 7 screens
tool/responsive/shoot_web.sh --no-build --dpr 1 --scrolls 1
tool/responsive/shoot_web.sh --no-build --viewports 320x640,1440x900 --routes home,matches --match-id <id>
SHOTS_DIR=/some/dir tool/responsive/shoot_web.sh     # output root (default build/responsive_shots/<timestamp>)
```
Viewports: 320x640, 360x780, 390x844, 412x915, 600x960, 820x1180, 1280x800,
1440x900. Each run writes `index.html` (contact sheet), `console.log` (browser
errors/warnings, failed requests) and `summary.json`. The match detail is the first card on Live (or `--match-id`).
See `python3 tool/responsive/shoot_web.py --help`.

**Web performance** (profile build into `build/web_profile`; FCP, Flutter first
frame, first API response, time until live match cards are visible, transfer size)
```sh
tool/responsive/shoot_web.sh --profile                       # 2 cold loads per viewport
tool/responsive/shoot_web.sh --profile --cpu-throttle 4 --viewports 390x844 --perf-runs 3
```

**Real device (adb; uses the installed app, never installs)**
```sh
adb devices
tool/responsive/shoot_device.sh -s DEVICE_ID                 # walk all tabs + first match detail
tool/responsive/shoot_device.sh -s DEVICE_ID --sizes "native 720x1600@320 1600x2560@320"
tool/responsive/perf_device.sh  -s DEVICE_ID                 # scroll jank on the Live list
```
`--sizes` applies `wm size`/`wm density` overrides and always resets them on
exit (`adb -s DEVICE_ID shell wm size reset; adb -s DEVICE_ID shell wm density reset`
if a run was killed hard). realme/ColorOS and MIUI refuse these unless Developer
options > "Disable permission monitoring" is on. `perf_device.sh` reads
SurfaceFlinger timestats for the Flutter SurfaceView (jank % = frames presented
>= 1.5 vsync after the previous one) plus `dumpsys gfxinfo framestats` (hwui only,
normally 0 frames for Flutter). Measure a profile build
(`flutter install --profile -d DEVICE_ID`); debug builds are not representative.

**Widget-test screen matrix** (`test/support/screen_matrix.dart`): pumps any widget
at the same viewports x text scale {1.0, 1.3, 2.0} x light/dark and collects
RenderFlex/overflow errors with their source location.
```sh
flutter test test/responsive                                          # report only -> build/screen_matrix/home.txt
flutter test test/responsive --dart-define=SCREEN_MATRIX_STRICT=true  # fail on any overflow
```
Use it in a new test:
`await pumpScreenMatrix(tester, name: 'matches', build: (c) => MaterialApp(home: MatchesScreen()), setUp: (_) async => FakeApi(defaultRoutes()).install());`

## Structure
`lib/core` (theme, API client/cache, services, transforms, router/shell, shared widgets),
`lib/features/<feature>`; porting rules in `PORTING_GUIDE.md`.

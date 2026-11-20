# Cric Ticker — React Native → Flutter port: shared rules for every feature port

RN source (read-only reference): `../crickbex-app/` (App.tsx, src/screens, src/components, src/hooks, src/utils, src/types/cricket.ts, src/constants).
Flutter project: this folder. Package name `crickbex` (internal Dart package id, kept to avoid a mass import rewrite; user-facing brand strings live in `lib/core/brand/brand.dart` — never hard-code them) (imports: `package:crickbex/...` or relative).

## Core you MUST use (do not modify files under lib/core/ — if you think core needs a change, describe it in your final report instead)
- `lib/core/theme/app_theme.dart` — `AppColors.*` (ported 1:1 from RN theme.ts), `Spacing`, `Radii`, `AppText`, `Responsive.of(context)`.
- `lib/core/api/api_client.dart` — `ApiClient`, `ApiResponse` (`.data`, `.dataList`, `.dataMap`, `.pageInfo`, `.raw`), `ApiException` (`.isNotFound`, `.isNetwork`), `friendlyError(e)`.
- `lib/core/api/json.dart` — `JsonMap`, `J.map/list/maps/str/text/integer/number/boolean/at('a.b.c')`. The API is loosely typed: ALWAYS parse via J.* (numbers may be strings, fields missing). Never `as` cast raw JSON.
- `lib/core/api/api_cache.dart` — `ApiCache.get/set` + `CacheTtl` (port RN getCached/setCached usage where RN uses it).
- `lib/core/services/cricket_services.dart` — `MatchService.instance`, `PlayerService.instance`, `RankingService.instance` (same methods as RN services). For tests construct `MatchService(testClient(MockClient(...), baseUrl: 'http://test'))` (from `test/support/sbx1_server.dart`; serves legacy REST fixtures through the SBX1 client)`.
- `lib/core/utils/match_transform.dart` — `MatchSummary` (RN `Match`), `transformApiMatch(s)`, `matchIdOf`, `deriveIsLive`; `chase_summary.dart`; `fixture_status.dart` (`resolveSeriesFixtureDisplay`).
- `lib/core/widgets/` — `NetImage` (RN CachedImage), `ShimmerGroup`+`ShimmerBox`, `EmptyState`, `ErrorRetry`, `Pressable` (RN AnimatedPressable), `GlassCard`, `StatusBadge`, `AppTopBar` (RN AppBar), `ScreenTitle`, `PageTitle`, `SectionHeader`, `SectionTabs`+`SectionTabItem`, `SegmentedControl`+`SegmentOption`, `OfflineBanner`, `Loadable<T>` + `AutoRefresh` (async_value.dart).
- `lib/core/router/app_nav.dart` — navigate with `AppNav.match(context, matchId)`, `AppNav.player(context, playerKey, player: json)`, `AppNav.seriesDetail(context, seriesId, seriesName: ...)`, `AppNav.page(context, 'more'|'privacy'|'terms'|'about'|'contact'|'app-info')`, `AppNav.tab(context, AppTab.x)`, `AppNav.discover(context, DiscoverSection.x)`, `context.pop()`. Routes are in `lib/core/router/app_router.dart` (don't edit); see "Routes" below.
- `lib/core/storage/prefs.dart` — `AppPrefs` (onboarding flag, favorites, generic get/set).
- Ads: `lib/features/ads/ads.dart` — `ScreenBannerSlots(screen:, onlyPosition:, fullBleed:)`, `FixedBottomBanner(screen:)`, `ListNativeAd(placement:)`, `AdsManager.instance.recordDetailExit()`. Place them exactly where RN places them.

## Routes
- Bottom-bar tabs (fixed order, never reorder): Home `/home`, Live `/live`, Matches `/matches`, Discover `/discover`, Settings `/settings` (`AppTab`).
- Discover sections are pushed on the Discover stack: `/discover/series`, `/discover/rankings`, `/discover/players` (`DiscoverSection`). Legacy `/series`, `/ranking`, `/players` redirect there.
- Every tab root has the detail routes `match/:matchId`, `player/:playerKey`, `series-detail/:seriesId` and the info pages `privacy`, `terms`, `contact` (help and support), `about`, `app-info`, `more` (legacy; shows the Settings list).
- The RN "More" tab and the rating modal are gone: Settings holds theme, support, rating (store link), legal and about. Do not open a rating prompt from back/exit or on screen open; to mark a positive moment call `ReviewScope.read(context)?.requestReviewIfAppropriate(positiveMoment: true)`.

## Rules
1. Port behaviour and UI faithfully (layout, colors, texts, empty/error/loading states, pull-to-refresh, pagination, auto-refresh, tab behaviour). Read the RN file fully before writing the Dart version. Keep RN comments' intent where it explains a bug fix.
2. Data comes ONLY from the local API through the services above. No hardcoded/fake data in the app (fixtures are for tests only).
3. Performance (the app is tested on a mid-range Android phone for jank/hangs):
   - Long lists: `ListView.builder` / `SliverList` (never `Column` of hundreds of children inside a scroll view); give list items stable `ValueKey`s.
   - Images: always `NetImage` (it caches + decodes at display size).
   - No synchronous heavy work in `build`; parse/transform once when data arrives (store parsed view-models in state).
   - Timers/polling: cancel in `dispose`; pause when the route is not visible / app backgrounded (`AutoRefresh` does the lifecycle part); never `setState` after dispose (use `if (!mounted) return;` or `Loadable`).
   - Guard against double taps that push the same route twice.
   - Prefer `const` constructors.
4. Every interactive widget that a test needs to find gets a `ValueKey('<feature>_<name>')`.
5. Null-safety: no `!` on API data. A malformed/missing field must never crash a screen — degrade to '-'/empty.
6. Tests (required, in `test/<your feature dir>/`): use `package:flutter_test`, `package:http/testing.dart` `MockClient`, fixtures in `test/fixtures/*.json` (real responses captured from the local API — read them to learn the shapes). Cover:
   - unit tests for every parser/transform/helper you write (incl. malformed/empty JSON),
   - widget tests for each screen: loading (shimmer) → data, empty state, error state + Retry recovers, navigation taps (use a GoRouter in the test or assert AppNav calls via the router location), pull-to-refresh, pagination/load-more, tab switching,
   - regression tests for edge cases you find (e.g. missing scores, long names, 0 items, server 500, timeout).
   Wrap widgets in `MaterialApp` / `MaterialApp.router` as needed. Remember `SharedPreferences.setMockInitialValues({})` when prefs/cache are touched.
   Network images: in widget tests wrap with `HttpOverrides`-free approach — NetImage falls back gracefully; do not depend on images loading.
7. Before finishing run: `flutter analyze` (zero errors/warnings in your files) and `flutter test test/<your dir>` (all passing). Do NOT run device builds (`flutter run/build/install`) — the lead does device testing.
8. Only create/edit files inside the directories you own (listed in your task). Placeholders you own may be overwritten (keep the public class names + constructor signatures listed in them).
9. Final report: files created, what's ported, anything not ported and why, known gaps, tests added (+ pass count), and any core change you'd request.

#!/usr/bin/env python3
"""Responsive screenshot + perf harness for the Flutter web build (Playwright).

Captures every main route at every viewport (and device scale factor) into a
timestamped folder with a contact sheet (index.html), console log and
summary.json. Optional --perf mode records load timings per viewport.

Normally run through tool/responsive/shoot_web.sh (which builds the app first).
Direct use (expects a built app in build/web):

  python3 tool/responsive/shoot_web.py --serve build/web --out /tmp/shots
  python3 tool/responsive/shoot_web.py --url http://localhost:8099 --dpr 1,2,3
  python3 tool/responsive/shoot_web.py --serve build/web_profile --perf --cpu-throttle 4

Notes
- Flutter web renders into a canvas (CanvasKit): screenshots are viewport
  sized (the page itself never scrolls); use --scrolls N for extra frames
  scrolled with the mouse wheel.
- The harness turns on Flutter's semantics tree (clicks the hidden
  flt-semantics-placeholder) so it can read on-screen text, find the first
  live match card and detect when live data is visible. Rendering is unchanged.
- Onboarding is skipped by pre-seeding localStorage (shared_preferences web
  keys are prefixed with "flutter.").
- Routes use go_router's default hash URLs (#/live, #/matches ...).
"""
import argparse
import datetime as dt
import functools
import html
import http.server
import json
import os
import socketserver
import sys
import threading
import time

from playwright.sync_api import sync_playwright

VIEWPORTS = [
    (320, 640), (360, 780), (390, 844), (412, 915),
    (600, 960), (820, 1180), (1280, 800), (1440, 900),
]
ROUTES = [
    ("home", "/home"),
    ("live", "/live"),
    ("matches", "/matches"),
    ("discover", "/discover"),
    ("series", "/discover/series"),
    ("ranking", "/discover/rankings"),
    ("players", "/discover/players"),
    ("settings", "/settings"),
    ("search", "/home/search"),
]
INIT_SCRIPT = """
try {
  localStorage.setItem('flutter.hasSeenOnboarding', 'true');
} catch (e) {}
window.__cbx = {firstFrame: null};
window.addEventListener('flutter-first-frame', () => { window.__cbx.firstFrame = performance.now(); });
"""
ENABLE_SEMANTICS = "document.querySelector('flt-semantics-placeholder')?.click()"
SEMANTIC_TEXT = "(document.querySelector('flt-semantics-host')?.innerText || '')"
# A live-match card exposes "<team> vs <team>, live" as its semantics label.
LIVE_CARD_JS = """() => {
  const nodes = Array.from(document.querySelectorAll('flt-semantics'));
  return nodes.some(n => / vs .*, (live|upcoming|completed|result)/i.test(n.getAttribute('aria-label') || n.innerText || ''));
}"""


def serve(directory, port):
    handler = functools.partial(QuietHandler, directory=directory)
    socketserver.TCPServer.allow_reuse_address = True
    httpd = socketserver.ThreadingTCPServer(("127.0.0.1", port), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def wait_idle(page, extra_ms):
    try:
        page.wait_for_load_state("networkidle", timeout=20000)
    except Exception:
        pass
    page.wait_for_timeout(extra_ms)


def goto_route(page, route, settle_ms):
    page.evaluate(f"location.hash = '#{route}'")
    page.wait_for_timeout(300)
    wait_idle(page, settle_ms)


def open_first_match(page, timeout_s=15):
    """From the home screen, tap the first match card (go_router `push` does
    not change the URL on web, so the detail page is reached by tapping)."""
    loc = page.locator("flt-semantics[aria-label*=' vs ']")
    deadline = time.time() + timeout_s
    while loc.count() == 0 and time.time() < deadline:
        page.evaluate(ENABLE_SEMANTICS)
        page.wait_for_timeout(300)
    if loc.count() == 0:
        print("WARNING: no match card found on home; pass --match-id")
        return False
    loc.first.evaluate("e => e.click()")
    return True


def new_context(browser, w, h, dpr, dark):
    return browser.new_context(
        viewport={"width": w, "height": h},
        device_scale_factor=dpr,
        is_mobile=w < 600,
        has_touch=w < 1024,
        color_scheme="dark" if dark else "light",
    )


def shoot(args, browser, base, out):
    dprs = [float(d) for d in args.dpr.split(",")]
    vps = VIEWPORTS if not args.viewports else [tuple(int(x) for x in v.split("x")) for v in args.viewports.split(",")]
    routes = list(ROUTES)
    if args.routes:
        wanted = set(args.routes.split(","))
        routes = [r for r in routes if r[0] in wanted]
    match_route = f"/home/match/{args.match_id}" if args.match_id else None
    shots, console = [], []

    for dpr in dprs:
        for (w, h) in vps:
            tag = f"{w}x{h}@{dpr:g}x"
            ctx = new_context(browser, w, h, dpr, args.dark)
            ctx.add_init_script(INIT_SCRIPT)
            page = ctx.new_page()
            page.on("console", lambda m, tag=tag: console.append(f"[{tag}] {m.type}: {m.text}") if m.type in ("error", "warning") else None)
            page.on("pageerror", lambda e, tag=tag: console.append(f"[{tag}] pageerror: {e}"))
            page.on("requestfailed", lambda r, tag=tag: console.append(f"[{tag}] requestfailed: {r.url[:80]} {r.failure}"))
            page.goto(base + "/#/home")
            wait_idle(page, args.settle_ms + 1500)
            page.evaluate(ENABLE_SEMANTICS)
            plan = list(routes)
            if not args.no_detail:
                # None = reach the detail page by tapping the first card on home.
                plan.append(("match_detail", match_route))
            for name, route in plan:
                if route is None:
                    goto_route(page, "/home", 500)
                    if not open_first_match(page):
                        continue
                    wait_idle(page, args.settle_ms + 500)
                    route = "(first match card)"
                else:
                    goto_route(page, route, args.settle_ms)
                for i in range(args.scrolls + 1):
                    if i:
                        page.mouse.move(w / 2, h / 2)
                        page.mouse.wheel(0, h * 0.8)
                        page.wait_for_timeout(700)
                    fname = f"{name}_{w}x{h}_dpr{dpr:g}{'' if i == 0 else f'_s{i}'}.png"
                    page.screenshot(path=os.path.join(out, fname))
                    text = page.evaluate(SEMANTIC_TEXT)
                    shots.append({"file": fname, "route": route, "name": name, "w": w, "h": h, "dpr": dpr,
                                  "scroll": i, "chars": len(text)})
                print(f"  {tag} {name}")
            ctx.close()
    return shots, console


def perf(args, browser, base):
    """Cold-load timings per viewport (fresh context each run)."""
    vps = VIEWPORTS if not args.viewports else [tuple(int(x) for x in v.split("x")) for v in args.viewports.split(",")]
    rows = []
    for (w, h) in vps:
        for run in range(args.perf_runs):
            ctx = new_context(browser, w, h, 1, args.dark)
            ctx.add_init_script(INIT_SCRIPT)
            page = ctx.new_page()
            cdp = ctx.new_cdp_session(page)
            cdp.send("Performance.enable")
            if args.cpu_throttle > 1:
                cdp.send("Emulation.setCPUThrottlingRate", {"rate": args.cpu_throttle})
            api_first = {}

            def on_resp(r, api_first=api_first, page=page):
                if "/api/x/" in r.url and "t" not in api_first:
                    api_first["t"] = page.evaluate("performance.now()")
            page.on("response", on_resp)
            page.goto(base + "/#/home", wait_until="commit")
            data_ms = None
            deadline = time.time() + 60
            while time.time() < deadline:
                try:
                    page.evaluate(ENABLE_SEMANTICS)
                    if page.evaluate(LIVE_CARD_JS):
                        data_ms = page.evaluate("performance.now()")
                        break
                except Exception:
                    pass
                page.wait_for_timeout(100)
            wait_idle(page, 500)
            m = page.evaluate("""() => {
              const p = {}; performance.getEntriesByType('paint').forEach(e => p[e.name] = e.startTime);
              const nav = performance.getEntriesByType('navigation')[0] || {};
              const res = performance.getEntriesByType('resource');
              const bytes = res.reduce((a, r) => a + (r.transferSize || 0), 0);
              return {fp: p['first-paint'], fcp: p['first-contentful-paint'], dcl: nav.domContentLoadedEventEnd,
                      load: nav.loadEventEnd, firstFrame: window.__cbx && window.__cbx.firstFrame,
                      transferKB: Math.round(bytes / 1024), heapMB: performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576) : null};
            }""")
            m.update({"viewport": f"{w}x{h}", "run": run, "firstApiResponse": api_first.get("t"), "liveDataVisible": data_ms,
                      "cpuThrottle": args.cpu_throttle})
            rows.append(m)
            fmt = lambda v: "-" if v is None else f"{v:.0f}"
            print(f"  perf {w}x{h} run{run}: FCP {fmt(m['fcp'])}ms, flutter first frame {fmt(m['firstFrame'])}ms, "
                  f"first API {fmt(m['firstApiResponse'])}ms, live data visible {fmt(data_ms)}ms, "
                  f"{m['transferKB']}KB, heap {m['heapMB']}MB")
            ctx.close()
    return rows


def contact_sheet(out, shots, console):
    by_name = {}
    for s in shots:
        by_name.setdefault(s["name"], []).append(s)
    parts = ["<!doctype html><meta charset=utf-8><title>CrickBex responsive shots</title>",
             "<style>body{font:13px system-ui;background:#111;color:#eee;margin:16px}"
             "section{margin-bottom:32px}.row{display:flex;gap:12px;overflow-x:auto;align-items:flex-start}"
             "figure{margin:0}img{height:420px;border:1px solid #444}figcaption{opacity:.7}</style>"]
    for name, items in by_name.items():
        parts.append(f"<section><h2>{html.escape(name)}</h2><div class=row>")
        for s in items:
            parts.append(f"<figure><a href='{s['file']}'><img loading=lazy src='{s['file']}'></a>"
                         f"<figcaption>{s['w']}x{s['h']} @{s['dpr']:g}x{' scroll ' + str(s['scroll']) if s['scroll'] else ''}</figcaption></figure>")
        parts.append("</div></section>")
    if console:
        parts.append("<h2>Console errors / warnings</h2><pre>" + html.escape("\n".join(console)) + "</pre>")
    with open(os.path.join(out, "index.html"), "w") as f:
        f.write("\n".join(parts))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", help="Base URL of an already served build (e.g. http://localhost:8099)")
    ap.add_argument("--serve", help="Serve this directory (e.g. build/web) on --port for the run")
    ap.add_argument("--port", type=int, default=8099)
    ap.add_argument("--out", help="Output folder (default: $SHOTS_DIR or build/responsive_shots, + timestamp)")
    ap.add_argument("--dpr", default="1,2,3", help="Device scale factors, comma separated (default 1,2,3)")
    ap.add_argument("--viewports", help="Override viewports, e.g. 320x640,1440x900")
    ap.add_argument("--routes", help="Subset of: home,live,matches,discover,series,ranking,players,settings,search")
    ap.add_argument("--match-id", help="Match id for the detail screenshot (default: first card on home)")
    ap.add_argument("--no-detail", action="store_true", help="Skip the match detail screenshot")
    ap.add_argument("--scrolls", type=int, default=0, help="Extra scrolled screenshots per route")
    ap.add_argument("--settle-ms", type=int, default=1500, help="Wait after network idle per route")
    ap.add_argument("--dark", action="store_true", help="prefers-color-scheme: dark")
    ap.add_argument("--perf", action="store_true", help="Record load timings instead of screenshots")
    ap.add_argument("--perf-runs", type=int, default=2)
    ap.add_argument("--cpu-throttle", type=float, default=1, help="CDP CPU slowdown for --perf (4 ~ mid phone)")
    ap.add_argument("--headed", action="store_true")
    args = ap.parse_args()

    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    root = args.out or os.path.join(os.environ.get("SHOTS_DIR", "build/responsive_shots"), stamp)
    os.makedirs(root, exist_ok=True)

    httpd = None
    base = args.url
    if args.serve:
        httpd = serve(os.path.abspath(args.serve), args.port)
        base = f"http://localhost:{args.port}"
    if not base:
        ap.error("pass --url or --serve")
    base = base.rstrip("/")

    with sync_playwright() as p:
        try:
            browser = p.chromium.launch(channel="chrome", headless=not args.headed)
        except Exception:
            browser = p.chromium.launch(headless=not args.headed)  # python3 -m playwright install chromium
        summary = {"base": base, "time": stamp}
        if args.perf:
            summary["perf"] = perf(args, browser, base)
            print(f"perf results: {os.path.join(root, 'summary.json')}")
        else:
            shots, console = shoot(args, browser, base, root)
            summary.update(shots=shots, console=console)
            contact_sheet(root, shots, console)
            with open(os.path.join(root, "console.log"), "w") as f:
                f.write("\n".join(console))
            empty = [s["file"] for s in shots if s["chars"] < 20]
            print(f"{len(shots)} screenshots -> {root}/index.html; console errors/warnings: {len(console)}")
            if empty:
                print(f"WARNING: little or no on-screen text in: {', '.join(empty[:10])}")
        with open(os.path.join(root, "summary.json"), "w") as f:
            json.dump(summary, f, indent=2)
        browser.close()
    if httpd:
        httpd.shutdown()
    print(root)


if __name__ == "__main__":
    sys.exit(main())

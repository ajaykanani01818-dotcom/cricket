#!/usr/bin/env python3
"""Build every Cric Ticker icon / logo / splash asset from the owner's sources.

Sources (kept in Y/docs/brand/source/):
  icon_source.png    1254x1254 RGB: orange "C" ball + speed lines on a dark rounded
                     square, with a black outer frame and glossy swooshes baked in.
  logo_source.png    2126x740 RGBA: flat orange C mark + "Cric Ticker" in ink.
  splash_source.gif  410x413, 8 frames: stadium -> C sweep -> logo storyboard.

Run from crickbex_flutter/:  python3 -I tool/brand/build_assets.py
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.abspath(os.path.join(ROOT, "..", "docs", "brand", "source"))
OUT_DOC = os.path.abspath(os.path.join(ROOT, "..", "docs", "brand", "assets"))

BG = (0x17, 0x13, 0x0F)          # brand dark canvas
INK = (0x1C, 0x18, 0x14)
LIGHT_INK = (0xF7, 0xF1, 0xEA)
ORANGE = (0xED, 0x80, 0x0C)


def p(*parts):
    path = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path


def save(img, *parts, **kw):
    path = p(*parts)
    img.save(path, optimize=True, **kw)
    return path


# ---------------------------------------------------------------- icon mark
def extract_icon_mark():
    """Key the orange/white mark off the dark background (drops the black frame,
    the rounded square and the grey gloss swooshes). Returns a tight RGBA crop."""
    src = Image.open(os.path.join(SRC, "icon_source.png")).convert("RGB")
    w, h = src.size
    px = src.load()
    out = Image.new("RGBA", (w, h))
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            # Gloss swooshes are low-saturation greys (R<=70); the mark is
            # orange (R high, B low) or white stitches (all high).
            a = (r - 72) / 78.0
            a = 0.0 if a < 0 else 1.0 if a > 1 else a
            # Drop grey/neutral pixels (the rounded-square edge highlight and
            # gloss): keep saturated orange and near-white stitches only.
            sat = max(r, g, b) - min(r, g, b)
            if sat < 60 and min(r, g, b) < 170:
                a = 0.0
            op[x, y] = (r, g, b, int(a * 255))
    bbox = out.getchannel("A").point(lambda v: 255 if v > 60 else 0).getbbox()
    return out.crop(bbox)


def fit(mark, box_w, box_h):
    m = mark.copy()
    m.thumbnail((box_w, box_h), Image.LANCZOS)
    return m


def place(canvas, mark, cx=None, cy=None, dx=0):
    cw, ch = canvas.size
    x = (cw - mark.width) // 2 + dx if cx is None else cx - mark.width // 2
    y = (ch - mark.height) // 2 if cy is None else cy - mark.height // 2
    canvas.alpha_composite(mark, (x, y))
    return canvas


def full_square_icon(mark, size, scale=0.74):
    """Opaque full-bleed square (iOS / Play / web): dark canvas + mark."""
    c = Image.new("RGBA", (size, size), BG + (255,))
    m = fit(mark, int(size * scale), int(size * scale))
    place(c, m, dx=int(size * 0.01))
    return c.convert("RGB")


def rounded(img, radius_ratio=0.22, circle=False):
    size = img.width
    mask = Image.new("L", (size * 4, size * 4), 0)
    d = ImageDraw.Draw(mask)
    if circle:
        d.ellipse((0, 0, size * 4 - 1, size * 4 - 1), fill=255)
    else:
        d.rounded_rectangle((0, 0, size * 4 - 1, size * 4 - 1), radius=int(size * 4 * radius_ratio), fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


# ---------------------------------------------------------------- logo
def logo_variants():
    src = Image.open(os.path.join(SRC, "logo_source.png")).convert("RGBA")
    bbox = src.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
    src = src.crop(bbox)
    pad = int(src.height * 0.06)
    canvas = Image.new("RGBA", (src.width + pad * 2, src.height + pad * 2), (0, 0, 0, 0))
    canvas.alpha_composite(src, (pad, pad))
    src = canvas
    light, dark = Image.new("RGBA", src.size), Image.new("RGBA", src.size)
    sp, lp, dp = src.load(), light.load(), dark.load()
    for y in range(src.height):
        for x in range(src.width):
            r, g, b, a = sp[x, y]
            if a == 0:
                continue
            orange = r > 150 and r - b > 90
            col = ORANGE if orange else INK
            lp[x, y] = col + (a,)
            dp[x, y] = (ORANGE if orange else LIGHT_INK) + (a,)
    # mark = the C on the left: find the first fully empty column gap after it
    alpha = src.getchannel("A")
    cols = [any(alpha.getpixel((x, y)) > 16 for y in range(0, src.height, 2)) for x in range(src.width)]
    x = 0
    while x < len(cols) and not cols[x]:
        x += 1
    while x < len(cols) and cols[x]:
        x += 1
    mark = light.crop((0, 0, x + pad // 2, src.height))
    mb = mark.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
    mark = mark.crop(mb)
    return light, dark, mark


# ---------------------------------------------------------------- splash bg
def splash_background():
    """Frame 0 of the GIF = the empty stadium. Upscale and extend to a tall
    phone canvas (1080x2400): black sky on top, pitch glow kept near the bottom."""
    g = Image.open(os.path.join(SRC, "splash_source.gif"))
    g.seek(0)
    f = g.convert("RGB")
    w = 1080
    scaled = f.resize((w, int(f.height * w / f.width)), Image.LANCZOS)
    scaled = scaled.filter(ImageFilter.GaussianBlur(1.2))  # hide upscale blockiness
    canvas = Image.new("RGB", (w, 2400), (0, 0, 0))
    y = 2400 - scaled.height - 220
    canvas.paste(scaled, (0, y))
    # fade the pasted band's top edge into the black sky
    grad = Image.new("L", (1, 260))
    for i in range(260):
        grad.putpixel((0, i), int(255 * i / 259))
    mask = Image.new("L", (w, scaled.height), 255)
    mask.paste(grad.resize((w, 260)), (0, 0))
    canvas2 = Image.new("RGB", canvas.size, (0, 0, 0))
    canvas2.paste(scaled, (0, y), mask)
    # extend the floor below the band with its last row colour
    floor = scaled.crop((0, scaled.height - 2, w, scaled.height - 1)).resize((w, 2400 - (y + scaled.height)))
    canvas2.paste(floor, (0, y + scaled.height))
    return canvas2


def main():
    mark = extract_icon_mark()
    os.makedirs(OUT_DOC, exist_ok=True)
    mark.save(os.path.join(OUT_DOC, "icon_mark_on_dark.png"))

    # ---- Android adaptive icon (108dp canvas; safe circle 66dp) -------------
    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for d, s in densities.items():
        fg_size = int(108 * s)
        fg = Image.new("RGBA", (fg_size, fg_size), (0, 0, 0, 0))
        # wide mark (aspect ~1.4): 56dp wide keeps the C tips inside the 66dp safe circle
        place(fg, fit(mark, int(56 * s), int(56 * s)), dx=int(1 * s))
        save(fg, "android/app/src/main/res", f"mipmap-{d}", "ic_launcher_foreground.png")
        mono = Image.new("RGBA", fg.size, (0, 0, 0, 0))
        mono.putalpha(fg.getchannel("A"))
        white = Image.new("RGBA", fg.size, (255, 255, 255, 255))
        white.putalpha(fg.getchannel("A"))
        save(white, "android/app/src/main/res", f"mipmap-{d}", "ic_launcher_monochrome.png")
        legacy = int(48 * s)
        sq = full_square_icon(mark, legacy * 4, scale=0.70).resize((legacy, legacy), Image.LANCZOS)
        save(rounded(sq, 0.22), "android/app/src/main/res", f"mipmap-{d}", "ic_launcher.png")
        save(rounded(sq, circle=True), "android/app/src/main/res", f"mipmap-{d}", "ic_launcher_round.png")
        # Android 12+ splash icon: 288dp canvas, artwork inside the 192dp circle
        sp_size = int(288 * s)
        spl = Image.new("RGBA", (sp_size, sp_size), (0, 0, 0, 0))
        place(spl, fit(mark, int(176 * s), int(176 * s)), dx=int(2 * s))
        save(spl, "android/app/src/main/res", f"drawable-{d}", "splash_icon.png")
        # pre-12 launch_background reuses splash_icon (same 288dp geometry as the intro's first frame)

    adaptive = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
"""
    for n in ("ic_launcher.xml", "ic_launcher_round.xml"):
        with open(p("android/app/src/main/res/mipmap-anydpi-v26", n), "w") as fh:
            fh.write(adaptive)
    with open(p("android/app/src/main/res/values/ic_launcher_background.xml"), "w") as fh:
        fh.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#17130F</color>\n</resources>\n')

    # ---- Play Store / iOS / web -------------------------------------------
    master = full_square_icon(mark, 1024, scale=0.72)
    master.save(os.path.join(OUT_DOC, "app_icon_1024.png"), optimize=True)
    full_square_icon(mark, 2048, scale=0.72).resize((512, 512), Image.LANCZOS).save(
        os.path.join(OUT_DOC, "play_store_icon_512.png"), optimize=True)
    contents = json.load(open(p("ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json")))
    for img in contents["images"]:
        fn = img.get("filename")
        if not fn:
            continue
        base = float(img["size"].split("x")[0])
        scale = int(img["scale"].rstrip("x"))
        px = int(round(base * scale))
        master.resize((px, px), Image.LANCZOS).save(p("ios/Runner/Assets.xcassets/AppIcon.appiconset", fn), optimize=True)
    for n, sz in (("Icon-192.png", 192), ("Icon-512.png", 512)):
        rounded(master.resize((sz, sz), Image.LANCZOS), 0.22).save(p("web/icons", n), optimize=True)
    for n, sz in (("Icon-maskable-192.png", 192), ("Icon-maskable-512.png", 512)):
        full_square_icon(mark, sz * 2, scale=0.62).resize((sz, sz), Image.LANCZOS).save(p("web/icons", n), optimize=True)
    # favicon: the C alone reads better than C+speed lines at 32px
    cmark = mark.crop((int(mark.width * 0.36), 0, mark.width, mark.height))
    fav = Image.new("RGBA", (128, 128), BG + (255,))
    place(fav, fit(cmark, 104, 104))
    rounded(fav, 0.22).resize((32, 32), Image.LANCZOS).save(p("web", "favicon.png"), optimize=True)

    # ---- iOS launch image (mark on dark) --------------------------------------
    for sc, n in ((1, "LaunchImage.png"), (2, "LaunchImage@2x.png"), (3, "LaunchImage@3x.png")):
        fit(mark, 150 * sc, 150 * sc).save(p("ios/Runner/Assets.xcassets/LaunchImage.imageset", n), optimize=True)

    # ---- In-app logos ------------------------------------------------------------
    light, dark, flat_mark = logo_variants()
    for img, n in ((light, "logo_light.png"), (dark, "logo_dark.png")):
        im = img.copy()
        im.thumbnail((1200, 1200), Image.LANCZOS)
        save(im, "assets/brand", n)
        img.save(os.path.join(OUT_DOC, n))
    fm = flat_mark.copy()
    fm.thumbnail((256, 256), Image.LANCZOS)
    save(fm, "assets/brand", "logo_mark.png")
    im = mark.copy()
    im.thumbnail((720, 720), Image.LANCZOS)
    save(im, "assets/brand", "icon_mark.png")       # glowing C + speed lines (dark bg only)

    # ---- Splash background --------------------------------------------------------
    bg = splash_background()
    save(bg, "assets/brand", "splash_stadium.jpg", quality=82, progressive=True)

    print("mark", mark.size, "flat mark", flat_mark.size, "logo", light.size)
    for f in ("assets/brand/logo_light.png", "assets/brand/logo_dark.png", "assets/brand/logo_mark.png",
              "assets/brand/icon_mark.png", "assets/brand/splash_stadium.jpg"):
        print(f, os.path.getsize(p(f)), "bytes")


if __name__ == "__main__":
    sys.exit(main())

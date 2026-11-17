#!/usr/bin/env python3
"""Draws the Lychnion app icons from the 64-unit logo master.

    build/route-venv/bin/python -I tool/build_icons.py

Writes (into the repo):
- iOS: every PNG listed in ios/Runner/Assets.xcassets/AppIcon.appiconset
- Android: mipmap-*/ic_launcher.png (legacy), and for Android 8+ the adaptive
  icon: a Night background colour, mipmap-*/ic_launcher_foreground.png and
  ic_launcher_monochrome.png (themed icons, Android 13+)
- macOS: every PNG in macos/Runner/Assets.xcassets/AppIcon.appiconset

The drawing follows the brand canvas (boards 2 and 3): an open roof, the
amber light and a small pointer, light on Night. Icons drawn at 64 px or
less use the small drawing (heavier roof, larger light). Each icon is drawn
at 4x and scaled down for smooth edges.
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent

NIGHT = (0x16, 0x23, 0x3F, 255)
MOON = (0xED, 0xEB, 0xE4, 255)
GLOW = (0xF2, 0xB5, 0x44, 255)
WHITE = (255, 255, 255, 255)

# (roof points, roof width, light centre y, light radius, pointer, pointer stroke)
FULL = ([(12, 25), (32, 10), (52, 25)], 5, 36, 11, [(26.5, 51), (37.5, 51), (32, 59)], 2)
SMALL = ([(10, 25), (32, 9), (54, 25)], 8, 37, 12.5, [(25, 52), (39, 52), (32, 61)], 3)

SS = 4  # supersampling


def mark(img, box, small, ink=MOON, light=GLOW):
    """Draws the mark into the square box (x, y, size) of img."""
    x0, y0, size = box
    s = size / 64
    roof, rw, cy, r, ptr, pw = SMALL if small else FULL
    d = ImageDraw.Draw(img)

    def p(pt):
        return (x0 + pt[0] * s, y0 + pt[1] * s)

    def round_line(points, w):
        pts = [p(q) for q in points]
        d.line(pts, fill=ink, width=round(w * s))
        for q in pts:
            d.ellipse([q[0] - w * s / 2, q[1] - w * s / 2, q[0] + w * s / 2, q[1] + w * s / 2], fill=ink)

    round_line(roof, rw)
    d.polygon([p(q) for q in ptr], fill=ink)
    round_line(ptr + [ptr[0]], pw)
    c = p((32, cy))
    d.ellipse([c[0] - r * s, c[1] - r * s, c[0] + r * s, c[1] + r * s], fill=light)


def render(px, draw):
    big = Image.new("RGBA", (px * SS, px * SS), (0, 0, 0, 0))
    draw(big, px * SS)
    return big.resize((px, px), Image.LANCZOS)


def square_icon(px, scale=124 / 180):
    """Night square with the mark (iOS: the system rounds the corners)."""
    def draw(img, n):
        ImageDraw.Draw(img).rectangle([0, 0, n, n], fill=NIGHT)
        m = n * scale
        mark(img, ((n - m) / 2, (n - m) / 2, m), small=px <= 64)
    return render(px, draw).convert("RGB")


def rounded_icon(px, inset=100 / 1024, radius=185 / 1024):
    """macOS: rounded Night tile with a margin, like other Mac apps."""
    def draw(img, n):
        a, b = n * inset, n * (1 - inset)
        ImageDraw.Draw(img).rounded_rectangle([a, a, b, b], radius=n * radius, fill=NIGHT)
        t = b - a
        m = t * 124 / 180
        mark(img, (a + (t - m) / 2, a + (t - m) / 2, m), small=px <= 64)
    return render(px, draw)


def foreground(px, ink=MOON, light=GLOW):
    """Android adaptive foreground: 108 dp layer, mark inside the 66 dp zone."""
    def draw(img, n):
        m = n * 60 / 108
        mark(img, ((n - m) / 2, (n - m) / 2, m), small=False, ink=ink, light=light)
    return render(px, draw)


def ios():
    d = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for im in json.loads((d / "Contents.json").read_text())["images"]:
        if "filename" not in im:
            continue
        pt = float(im["size"].split("x")[0])
        px = round(pt * int(im["scale"].rstrip("x")))
        square_icon(px).save(d / im["filename"])
        print("ios", im["filename"], px)


def macos():
    d = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for im in json.loads((d / "Contents.json").read_text())["images"]:
        pt = float(im["size"].split("x")[0])
        px = round(pt * int(im["scale"].rstrip("x")))
        rounded_icon(px).save(d / im["filename"])
        print("macos", im["filename"], px)


ANDROID = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def android():
    res = ROOT / "android/app/src/main/res"
    for name, k in ANDROID.items():
        d = res / f"mipmap-{name}"
        square_icon(round(48 * k), scale=0.62).save(d / "ic_launcher.png")
        foreground(round(108 * k)).save(d / "ic_launcher_foreground.png")
        foreground(round(108 * k), ink=WHITE, light=WHITE).save(d / "ic_launcher_monochrome.png")
        print("android", name)
    v26 = res / "mipmap-anydpi-v26"
    v26.mkdir(exist_ok=True)
    (v26 / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        '</adaptive-icon>\n'
    )
    (res / "values/ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        '    <color name="ic_launcher_background">#16233F</color>\n'
        '</resources>\n'
    )


if __name__ == "__main__":
    ios()
    macos()
    android()

#!/usr/bin/env python3
"""Makes the app's brand fonts from the Google Fonts originals.

    build/route-venv/bin/python -I tool/build_fonts.py <download dir>

The download dir holds, from github.com/google/fonts (all SIL OFL 1.1):
    bizudpgothic_BIZUDPGothic-Regular.ttf, bizudpgothic_BIZUDPGothic-Bold.ttf
    lexend_Lexend[wght].ttf

Writes assets/fonts/ (in git):
- BIZUDPGothic-{Regular,Bold}.ttf: app text. Cut down to ASCII, Latin-1,
  common punctuation and symbols, kana, and the JIS X 0208 kanji (levels 1
  and 2, about 6,400), plus every character in the app's own strings and
  package sources. Rarer characters (some place names) fall back to the
  system font.
- Lexend-{Medium,SemiBold}.ttf: the wordmark and English headings. Fixed
  weights cut from the variable font, Latin only.
- OFL.txt for both families.

Needs fonttools (pip install fonttools).
"""
import shutil
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/fonts"


def jis_chars():
    """Every character in JIS X 0208 (what Shift_JIS can encode)."""
    chars = set()
    for cp in range(0x20, 0x10000):
        ch = chr(cp)
        try:
            ch.encode("shift_jis")
        except UnicodeEncodeError:
            continue
        chars.add(cp)
    return chars


def own_chars():
    """Characters in the app's strings and the package sources."""
    chars = set()
    for pattern in ("lib/**/*.dart", "tool/packages/*.json", "tool/maps/*.json", "assets/downloads/*.json"):
        for f in ROOT.glob(pattern):
            chars.update(ord(c) for c in f.read_text(encoding="utf-8"))
    return {c for c in chars if c >= 0x20}


def ranges(*spans):
    return {cp for a, b in spans for cp in range(a, b + 1)}


def subset_font(src, dst, unicodes):
    opts = subset.Options()
    opts.layout_features = ["*"]  # keep vertical forms, kerning, palt
    opts.name_IDs = ["*"]
    opts.name_languages = ["*"]
    opts.notdef_outline = True
    opts.hinting = False
    font = TTFont(src)
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=sorted(unicodes))
    sub.subset(font)
    font.save(dst)


def main(dl):
    dl = Path(dl)
    OUT.mkdir(parents=True, exist_ok=True)
    latin = ranges((0x20, 0x7E), (0xA0, 0x17F), (0x2000, 0x206F), (0x20AC, 0x20AC), (0x2190, 0x21FF), (0x2460, 0x24FF), (0x25A0, 0x25FF), (0x2600, 0x26FF))
    ja = latin | jis_chars() | own_chars() | ranges((0x3000, 0x30FF), (0xFF00, 0xFFEF))
    for w in ("Regular", "Bold"):
        dst = OUT / f"BIZUDPGothic-{w}.ttf"
        subset_font(dl / f"bizudpgothic_BIZUDPGothic-{w}.ttf", dst, ja)
        print(f"{dst.name}: {dst.stat().st_size / 1e6:.2f} MB")
    for name, wght in (("Medium", 500), ("SemiBold", 600)):
        tmp = OUT / f"Lexend-{name}.tmp.ttf"
        inst = instancer.instantiateVariableFont(TTFont(dl / "lexend_Lexend[wght].ttf"), {"wght": wght})
        inst.save(tmp)
        dst = OUT / f"Lexend-{name}.ttf"
        subset_font(tmp, dst, latin)
        tmp.unlink()
        print(f"{dst.name}: {dst.stat().st_size / 1e3:.0f} KB")
    shutil.copy(dl / "bizudpgothic_OFL.txt", OUT / "OFL-BIZUDPGothic.txt")
    shutil.copy(dl / "lexend_OFL.txt", OUT / "OFL-Lexend.txt")


if __name__ == "__main__":
    main(sys.argv[1])

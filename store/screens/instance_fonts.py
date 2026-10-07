#!/usr/bin/env python3
"""Static weights of the variable script fonts, for the screenshot test.

The Flutter test engine draws a variable font at its default instance (too
heavy for body text), and it only falls back to fonts named in
fontFamilyFallback, so the test loads one static file per weight under one
family (fonts/static/<Family>-<weight>.ttf). frame.py draws the captions
from the same folder. Needs fontTools:

  python3 -m venv /tmp/ft && /tmp/ft/bin/pip install fonttools
  /tmp/ft/bin/python store/screens/instance_fonts.py
"""
import pathlib

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

HERE = pathlib.Path(__file__).parent
# family -> weights: the Noto set serves the test (400-700) and the captions;
# Plus Jakarta Sans and Manrope serve only the captions (frame.py), which also
# needs them static: Pillow lays out a variable font with the default
# instance's advances, so a bold headline gets the spacing of a thin one.
FAMILIES = {
    **{f: [400, 500, 600, 700] for f in ["NotoSansArabic", "NotoSansDevanagari", "NotoSansJP", "NotoSansKR", "NotoSansSC", "NotoSansTC"]},
    "PlusJakartaSans": [500, 700, 800],
    "Manrope": [500, 700, 800],
}

out = HERE / "fonts" / "static"
out.mkdir(parents=True, exist_ok=True)
for fam, weights in FAMILIES.items():
    for w in weights:
        dest = out / f"{fam}-{w}.ttf"
        if dest.exists():
            continue
        font = TTFont(HERE / "fonts" / f"{fam}.ttf")
        axes = {a.axisTag: a.defaultValue for a in font["fvar"].axes}
        axes["wght"] = w
        if "wdth" in axes:
            axes["wdth"] = 100
        static = instantiateVariableFont(font, axes, updateFontNames=False)
        static["OS/2"].usWeightClass = w
        static.save(dest)
        print(dest.name, dest.stat().st_size)

# IBM Plex Sans with one script's glyphs merged in, per weight. A phone draws
# Japanese in an IBM Plex Sans label with its system font; the test engine has
# no system fonts and falls back only to families a style names, which shadcn
# components never do, so the test loads these as "IBM Plex Sans" itself.
# Plex wins every code point both fonts have (Latin stays Plex).
from fontTools.merge import Merger, Options  # noqa: E402

APP_FONTS = HERE.parents[1] / "assets" / "fonts"
PLEX = {400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold"}
merged = HERE / "fonts" / "merged"
merged.mkdir(parents=True, exist_ok=True)
for fam in ["NotoSansArabic", "NotoSansDevanagari", "NotoSansJP", "NotoSansKR", "NotoSansSC", "NotoSansTC"]:
    for w, plex in PLEX.items():
        dest = merged / f"IBMPlexSans+{fam}-{w}.ttf"
        if dest.exists():
            continue
        # tables only one side has (vertical metrics, BASE) would stop the merge
        noto = TTFont(out / f"{fam}-{w}.ttf")
        for tag in ("vhea", "vmtx", "VORG", "BASE", "meta", "DSIG", "STAT"):
            if tag in noto:
                del noto[tag]
        tmp = merged / f"_{fam}-{w}.ttf"
        noto.save(tmp)
        font = Merger(options=Options(drop_tables=["vhea", "vmtx", "VORG", "BASE", "meta", "DSIG", "STAT"])).merge(
            [str(APP_FONTS / f"IBMPlexSans-{plex}.ttf"), str(tmp)]
        )
        tmp.unlink()
        font.save(dest)
        print(dest.name, dest.stat().st_size)

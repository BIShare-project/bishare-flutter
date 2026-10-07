#!/usr/bin/env python3
"""Store screenshots in the App Store look: a blue ground, an eyebrow, a two-line
headline and a sub line, the raw app capture inside a device, and two badges.

Reads the raw captures of integration_test/store_screenshots_test.dart
(`<raw>/<preset>/<lang>/<n>_<screen>.png`) and writes the store files:

  python3 store/screens/frame.py --raw <dir> --out <dir> [--lang en] [--target ios_phone]

Targets (canvas size, raw preset it reads):
  ios_phone      1290x2796  App Store iPhone 6.9"/6.7" (APP_IPHONE_67)
  ios_ipad       2064x2752  App Store iPad 13" (APP_IPAD_PRO_3GEN_129)
  mac            2880x1800  Mac App Store (APP_DESKTOP)
  play_phone     1440x2560  Google Play phone (9:16; Play refuses sides over 2:1)
  play_tablet    1600x2560  Google Play 7" and 10" tablet

Captions and badge text live in captions.py, written per language by hand.
Fonts come from fetch_fonts.sh (SIL OFL, git-ignored).
"""

from __future__ import annotations

import argparse
import math
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from captions import CAPTIONS, CHIPS, SCREENS  # noqa: E402

HERE = pathlib.Path(__file__).parent
FONTS = HERE / "fonts"

# target: (width, height, device kind, raw preset folder)
TARGETS = {
    "ios_phone": (1290, 2796, "iphone", "ios_phone"),
    "ios_ipad": (2064, 2752, "ipad", "ios_ipad"),
    "mac": (2880, 1800, "mac", "mac"),
    "play_phone": (1440, 2560, "android", "android_phone"),
    "play_tablet": (1600, 2560, "android_tablet", "android_tablet"),
}
SELF = {"ios_phone": "iPhone 17", "ios_ipad": "iPad Pro", "mac": "MacBook Pro", "play_phone": "Pixel 9", "play_tablet": "Galaxy Tab S10"}

TOP = (40, 92, 222)
BOTTOM = (6, 14, 40)
GLOW = (78, 132, 236)
EYEBROW = (191, 219, 254)
INK = (255, 255, 255)
SUB = (214, 226, 250)
RIM = (58, 66, 88)
BEZEL = (4, 6, 12)
CHIP_INK = (15, 23, 42)
CHIP_SUB = (100, 116, 139)
BADGE = {"blue": (59, 130, 246), "green": (34, 197, 94), "orange": (245, 158, 11), "sky": (14, 165, 233), "violet": (139, 92, 246)}

# caption face per script; static files from instance_fonts.py, by weight
FACE = {
    "latin": "PlusJakartaSans",
    "ru": "Manrope",
    "ar": "NotoSansArabic",
    "hi": "NotoSansDevanagari",
    "ja": "NotoSansJP",
    "ko": "NotoSansKR",
    "zh-Hans": "NotoSansSC",
    "zh-Hant": "NotoSansTC",
}
# scripts where letter spacing would break the shaping or reads oddly
NO_TRACKING = {"ar", "hi", "ja", "ko", "zh-Hans", "zh-Hant"}
_cache: dict = {}


def face_for(lang: str) -> str:
    return FACE.get(lang, FACE["latin"])


def font(lang: str, size: int, weight: int) -> ImageFont.FreeTypeFont:
    """The caption face of `lang` at the nearest static weight on disk."""
    key = (lang, size, weight)
    if key not in _cache:
        fam = face_for(lang)
        have = sorted(int(p.stem.rsplit("-", 1)[1]) for p in (FONTS / "static").glob(f"{fam}-*.ttf"))
        w = min(have, key=lambda x: (abs(x - weight), -x))
        _cache[key] = ImageFont.truetype(str(FONTS / "static" / f"{fam}-{w}.ttf"), size, layout_engine=ImageFont.Layout.RAQM)
    return _cache[key]


def rtl(lang: str) -> bool:
    return lang == "ar"


def text_w(draw: ImageDraw.ImageDraw, s: str, f: ImageFont.FreeTypeFont, lang: str, tracking: float = 0) -> float:
    if tracking and lang not in NO_TRACKING:
        return sum(draw.textlength(c, font=f) for c in s) + tracking * (len(s) - 1)
    return draw.textlength(s, font=f, direction="rtl" if rtl(lang) else None)


def draw_text(draw, xy, s, f, fill, lang, tracking: float = 0):
    x, y = xy
    if tracking and lang not in NO_TRACKING:
        for c in s:
            draw.text((x, y), c, font=f, fill=fill)
            x += draw.textlength(c, font=f) + tracking
        return
    draw.text((x, y), s, font=f, fill=fill, direction="rtl" if rtl(lang) else None)


def wrap(draw, s: str, f, width: float, lang: str) -> list[str]:
    """Greedy wrap. Japanese and Chinese break between any two characters
    but keep a Latin word ("Wi-Fi", "100 GB") whole; other scripts break at
    spaces."""
    import re

    if lang in ("ja", "zh-Hans", "zh-Hant"):
        tokens = re.findall(r"[A-Za-z0-9][A-Za-z0-9\-.]*|\s+|.", s)
    else:
        tokens = re.findall(r"\S+|\s+", s)
    lines, line = [], ""
    for t in tokens:
        trial = line + t
        if line.strip() and not t.isspace() and text_w(draw, trial.rstrip(), f, lang) > width:
            lines.append(line.rstrip())
            line = t
        else:
            line = trial
    if line.strip():
        lines.append(line.strip())
    # no line may start with closing punctuation in CJK
    for i in range(1, len(lines)):
        while lines[i] and lines[i][0] in "、。，．！？）」』":
            lines[i - 1] += lines[i][0]
            lines[i] = lines[i][1:]
    return [l.strip() for l in lines if l.strip()]


def ground(w: int, h: int) -> Image.Image:
    im = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = (y / (h - 1)) ** 0.85
        d.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    r = max(w, h) * 0.42
    ImageDraw.Draw(glow).ellipse((w / 2 - r, -r * 0.9, w / 2 + r, r * 0.55), fill=GLOW + (120,))
    im = Image.alpha_composite(im.convert("RGBA"), glow.filter(ImageFilter.GaussianBlur(r * 0.35)))
    return im


# ---------------------------------------------------------------- status bars
def status_ios(screen: Image.Image, scale: float, island: bool = True) -> None:
    """9:41, the Dynamic Island and the right-hand icons, drawn in `scale` px per pt."""
    d = ImageDraw.Draw(screen)
    w = screen.width
    f = font("en", round(17 * scale), 600)
    cy = (21 if island else 12) * scale
    t = "9:41"
    tw = d.textlength(t, font=f)
    left = (w / 2 - 63 * scale) / 2 if island else 20 * scale
    d.text((left + (0 if not island else -tw / 2 + 14 * scale), cy - 11 * scale), t, font=f, fill=(255, 255, 255))
    if island:
        iw, ih = 126 * scale, 37 * scale
        d.rounded_rectangle((w / 2 - iw / 2, 11 * scale, w / 2 + iw / 2, 11 * scale + ih), radius=ih / 2, fill=(0, 0, 0))
    # battery
    right = w - (34 if island else 20) * scale
    bw, bh = 25 * scale, 12 * scale
    bx, by = right - bw, cy + 1.5 * scale - bh / 2
    d.rounded_rectangle((bx, by, bx + bw, by + bh), radius=3.5 * scale, outline=(255, 255, 255, 140), width=max(1, round(1 * scale)))
    d.rounded_rectangle((bx + 2 * scale, by + 2 * scale, bx + bw - 2 * scale, by + bh - 2 * scale), radius=2 * scale, fill=(255, 255, 255))
    d.rounded_rectangle((bx + bw + 1 * scale, by + 4 * scale, bx + bw + 2.5 * scale, by + bh - 4 * scale), radius=1 * scale, fill=(255, 255, 255, 140))
    # wifi
    wx = bx - 13 * scale
    for i, rad in enumerate((9.5, 6.2, 2.8)):
        rr = rad * scale
        if i < 2:
            d.arc((wx - rr, cy + 5 * scale - rr, wx + rr, cy + 5 * scale + rr), 225, 315, fill=(255, 255, 255), width=round(2 * scale))
        else:
            d.pieslice((wx - rr * 1.3, cy + 5 * scale - rr * 1.3, wx + rr * 1.3, cy + 5 * scale + rr * 1.3), 225, 315, fill=(255, 255, 255))
    # signal
    sx = wx - 30 * scale
    for i in range(4):
        hh = (4 + 2.6 * i) * scale
        x0 = sx + i * 4.6 * scale
        d.rounded_rectangle((x0, cy + 6 * scale - hh, x0 + 3 * scale, cy + 6 * scale), radius=1 * scale, fill=(255, 255, 255))


def status_android(screen: Image.Image, scale: float, hole: bool = True) -> None:
    d = ImageDraw.Draw(screen)
    w = screen.width
    f = font("en", round(14 * scale), 500)
    cy = 20 * scale
    d.text((22 * scale, cy - 9 * scale), "9:41", font=f, fill=(255, 255, 255))
    if hole:
        r = 6.5 * scale
        d.ellipse((w / 2 - r, cy - r, w / 2 + r, cy + r), fill=(0, 0, 0))
    # battery (upright), wifi, signal
    right = w - 20 * scale
    bw, bh = 7.5 * scale, 13 * scale
    d.rounded_rectangle((right - bw, cy - bh / 2, right, cy + bh / 2), radius=1.6 * scale, fill=(255, 255, 255))
    d.rectangle((right - bw * 0.65, cy - bh / 2 - 1.5 * scale, right - bw * 0.35, cy - bh / 2), fill=(255, 255, 255))
    sx = right - bw - 20 * scale
    d.polygon([(sx, cy + 6 * scale), (sx + 13 * scale, cy + 6 * scale), (sx + 13 * scale, cy - 7 * scale)], fill=(255, 255, 255))
    wx = sx - 12 * scale
    rr = 10 * scale
    d.pieslice((wx - rr, cy - 4 * scale - rr * 0.4, wx + rr, cy - 4 * scale + rr * 1.6), 225, 315, fill=(255, 255, 255))


# ---------------------------------------------------------------- badges
def glyph(size: int, kind: str, color) -> Image.Image:
    """A rounded colour tile with a simple white pictogram."""
    s = size * 4  # draw large, scale down for smooth edges
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, s - 1, s - 1), radius=s * 0.26, fill=color + (255,))
    W = (255, 255, 255, 255)
    lw = round(s * 0.075)
    c = s / 2
    if kind == "check":
        d.line([(s * 0.29, s * 0.52), (s * 0.44, s * 0.66), (s * 0.72, s * 0.36)], fill=W, width=lw, joint="curve")
    elif kind == "lock":
        d.rounded_rectangle((s * 0.3, s * 0.46, s * 0.7, s * 0.74), radius=s * 0.05, fill=W)
        d.arc((s * 0.36, s * 0.26, s * 0.64, s * 0.6), 180, 360, fill=W, width=lw)
        d.line([(s * 0.36, s * 0.43), (s * 0.36, s * 0.48)], fill=W, width=lw)
        d.line([(s * 0.64, s * 0.43), (s * 0.64, s * 0.48)], fill=W, width=lw)
    elif kind == "phone":
        d.rounded_rectangle((s * 0.35, s * 0.24, s * 0.65, s * 0.76), radius=s * 0.06, outline=W, width=lw)
        d.line([(s * 0.46, s * 0.68), (s * 0.54, s * 0.68)], fill=W, width=lw)
    elif kind == "link":
        for dx in (-0.09, 0.09):
            box = (c + s * dx - s * 0.17, c - s * 0.1, c + s * dx + s * 0.17, c + s * 0.1)
            d.rounded_rectangle(box, radius=s * 0.1, outline=W, width=lw)
    elif kind == "download":
        d.line([(c, s * 0.25), (c, s * 0.6)], fill=W, width=lw)
        d.line([(s * 0.36, s * 0.47), (c, s * 0.61), (s * 0.64, s * 0.47)], fill=W, width=lw, joint="curve")
        d.line([(s * 0.3, s * 0.74), (s * 0.7, s * 0.74)], fill=W, width=lw)
    elif kind == "qr":
        q = s * 0.13
        for x0, y0 in ((0.27, 0.27), (0.6, 0.27), (0.27, 0.6)):
            d.rectangle((s * x0, s * y0, s * x0 + q, s * y0 + q), outline=W, width=round(lw * 0.8))
        for x0, y0 in ((0.6, 0.6), (0.68, 0.68), (0.6, 0.7), (0.7, 0.6)):
            d.rectangle((s * x0, s * y0, s * x0 + q * 0.4, s * y0 + q * 0.4), fill=W)
    elif kind == "camera":
        d.rounded_rectangle((s * 0.24, s * 0.34, s * 0.76, s * 0.7), radius=s * 0.06, outline=W, width=lw)
        d.ellipse((c - s * 0.1, s * 0.42, c + s * 0.1, s * 0.62), outline=W, width=lw)
        d.rectangle((s * 0.4, s * 0.28, s * 0.56, s * 0.34), fill=W)
    elif kind == "users":
        d.ellipse((s * 0.27, s * 0.28, s * 0.45, s * 0.46), fill=W)
        d.pieslice((s * 0.2, s * 0.5, s * 0.52, s * 0.86), 180, 360, fill=W)
        d.ellipse((s * 0.55, s * 0.32, s * 0.7, s * 0.47), fill=W)
        d.pieslice((s * 0.5, s * 0.52, s * 0.78, s * 0.84), 180, 360, fill=W)
    elif kind == "noaccount":
        d.ellipse((c - s * 0.1, s * 0.25, c + s * 0.1, s * 0.45), fill=W)
        d.pieslice((c - s * 0.2, s * 0.5, c + s * 0.2, s * 0.9), 180, 360, fill=W)
        d.line([(s * 0.26, s * 0.26), (s * 0.74, s * 0.74)], fill=color + (255,), width=round(lw * 2.2))
        d.line([(s * 0.26, s * 0.26), (s * 0.74, s * 0.74)], fill=W, width=lw)
    return im.resize((size, size), Image.LANCZOS)


def chip(title: str, sub: str, kind: str, color: str, base: float, lang: str) -> Image.Image:
    pad = base * 0.022
    ic = round(base * 0.072)
    ft = font(lang, round(base * 0.03), 700)
    fs = font(lang, round(base * 0.021), 500)
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    tw = max(text_w(probe, title, ft, lang), text_w(probe, sub, fs, lang))
    w = round(pad * 2 + ic + pad * 0.9 + tw)
    h = round(pad * 2 + ic)
    m = round(base * 0.05)  # room for the shadow
    im = Image.new("RGBA", (w + 2 * m, h + 2 * m), (0, 0, 0, 0))
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
    radius = h * 0.32
    ImageDraw.Draw(sh).rounded_rectangle((m, m + base * 0.012, m + w, m + h + base * 0.012), radius=radius, fill=(2, 8, 30, 120))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(base * 0.018)))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((m, m, m + w, m + h), radius=radius, fill=(255, 255, 255, 250))
    g = glyph(ic, kind, BADGE[color])
    right_to_left = rtl(lang)
    gx = m + w - pad - ic if right_to_left else m + pad
    im.alpha_composite(g, (round(gx), round(m + pad)))
    ty = m + pad + ic * 0.02
    for s_, f_, fill, dy in ((title, ft, CHIP_INK, 0), (sub, fs, CHIP_SUB, ic * 0.56)):
        sw = text_w(d, s_, f_, lang)
        x = (gx - pad * 0.9 - sw) if right_to_left else (gx + ic + pad * 0.9)
        draw_text(d, (x, ty + dy), s_, f_, fill, lang)
    return im


# ---------------------------------------------------------------- devices
def device(raw: Image.Image, kind: str, dw: int) -> tuple[Image.Image, int]:
    """The capture inside a device body `dw` wide. Returns (image, rim+bezel inset)."""
    phone = kind in ("iphone", "android")
    rim = round(dw * (0.012 if phone else 0.008))
    bezel = round(dw * (0.022 if phone else 0.018))
    sw = dw - 2 * (rim + bezel)
    sh = round(raw.height * sw / raw.width)
    dh = sh + 2 * (rim + bezel)
    radius = round(dw * (0.135 if kind == "iphone" else 0.1 if kind == "android" else 0.05))
    body = Image.new("RGBA", (dw, dh), (0, 0, 0, 0))
    d = ImageDraw.Draw(body)
    d.rounded_rectangle((0, 0, dw - 1, dh - 1), radius=radius, fill=RIM + (255,))
    d.rounded_rectangle((rim, rim, dw - 1 - rim, dh - 1 - rim), radius=radius - rim, fill=BEZEL + (255,))
    screen = raw.convert("RGBA").resize((sw, sh), Image.LANCZOS)
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), radius=max(4, radius - rim - bezel), fill=255)
    body.paste(screen, (rim + bezel, rim + bezel), mask)
    # lit top edge
    d.arc((0, 0, radius * 2, radius * 2), 180, 270, fill=(120, 132, 160, 255), width=max(1, rim // 3))
    return body, rim + bezel


# where the two badges sit, as a fraction of the app screen's height (the
# same point of the UI on every device), so they cover nothing a screen is
# about: the first beside this device's card or the first row, the second
# beside a list
CHIP_Y = {
    "share": (0.165, 0.47),
    "link": (0.2, 0.46),
    "qr_beam": (0.19, 0.36),
    "rooms": (0.28, 0.5),
    "settings": (0.3, 0.5),
}

# logical width of each raw preset in points, so status bars scale right
LOGICAL_W = {"iphone": 440, "android": 412, "ipad": 1032, "android_tablet": 800}


def home_indicator(screen: Image.Image, scale: float, width_pt: float, bottom_pt: float) -> None:
    d = ImageDraw.Draw(screen)
    w, h = screen.size
    bw, bh = width_pt * scale, 5 * scale
    y = h - bottom_pt * scale - bh
    d.rounded_rectangle((w / 2 - bw / 2, y, w / 2 + bw / 2, y + bh), radius=bh / 2, fill=(255, 255, 255, 230))


def framed_screen(raw: Image.Image, kind: str) -> Image.Image:
    """The raw capture with a status bar on its top inset and the home
    indicator on its bottom one (the test leaves both insets empty)."""
    shot = raw.convert("RGBA")
    scale = shot.width / LOGICAL_W[kind]
    if kind == "iphone":
        home_indicator(shot, scale, 140, 8)
    elif kind == "ipad":
        home_indicator(shot, scale, 300, 7)
    elif kind in ("android", "android_tablet"):
        home_indicator(shot, scale, 108 if kind == "android" else 160, 9)
    if kind == "iphone":
        status_ios(shot, scale, island=True)
    elif kind == "ipad":
        status_ios(shot, scale, island=False)
    elif kind == "android":
        status_android(shot, scale, hole=True)
    elif kind == "android_tablet":
        status_android(shot, scale, hole=False)
    return shot


def mac_window(raw: Image.Image, ww: int) -> Image.Image:
    bar = round(raw.width * 28 / 1000)
    win = Image.new("RGBA", (raw.width, raw.height + bar), (0, 0, 0, 0))
    d = ImageDraw.Draw(win)
    r = round(raw.width * 0.012)
    d.rounded_rectangle((0, 0, raw.width - 1, raw.height + bar - 1), radius=r, fill=(26, 28, 36, 255))
    d.rectangle((0, bar - 1, raw.width, bar), fill=(40, 44, 56, 255))
    for i, col in enumerate(((255, 95, 87), (254, 188, 46), (40, 200, 64))):
        cx, cy, rr = bar * 0.75 + i * bar * 0.72, bar / 2, bar * 0.22
        d.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=col + (255,))
    ft = font("en", round(bar * 0.45), 600)
    t = "BIShare"
    d.text(((raw.width - d.textlength(t, font=ft)) / 2, bar * 0.24), t, font=ft, fill=(200, 205, 215, 255))
    mask = Image.new("L", raw.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, -r, raw.width - 1, raw.height - 1), radius=r, fill=255)
    win.paste(raw.convert("RGBA"), (0, bar), mask)
    d.rounded_rectangle((0, 0, raw.width - 1, raw.height + bar - 1), radius=r, outline=(90, 98, 120, 255), width=2)
    return win.resize((ww, round(win.height * ww / win.width)), Image.LANCZOS)


# ---------------------------------------------------------------- composition
def captions_block(canvas: Image.Image, lang: str, eyebrow: str, head: str, sub: str, base: float, top: float, max_w: float, single_line: bool = False) -> float:
    d = ImageDraw.Draw(canvas)
    w = canvas.width
    fe = font(lang, round(base * 0.027), 700)
    track = base * 0.011
    ew = text_w(d, eyebrow, fe, lang, track)
    draw_text(d, ((w - ew) / 2, top), eyebrow, fe, EYEBROW, lang, track)
    y = top + base * 0.06
    size = round(base * (0.05 if single_line else 0.092))
    parts = [head.replace("\n", " ")] if single_line else head.split("\n")
    # Keep the lines as written: shrink until each fits on one line. Only a
    # line that still does not fit at 72% of the size is wrapped, so a
    # headline never ends on a one-word orphan ("Envie para qualquer / um.").
    floor = size * 0.72
    while True:
        fh = font(lang, size, 800)
        if all(text_w(d, p, fh, lang) <= max_w for p in parts):
            lines = parts
            break
        if size * 0.95 < floor:
            lines = [l for p in parts for l in wrap(d, p, fh, max_w, lang)]
            break
        size = round(size * 0.95)
    lh = size * (1.06 if face_for(lang) in (FACE["latin"], FACE["ru"]) else 1.22)
    for l in lines:
        lw = text_w(d, l, fh, lang)
        draw_text(d, ((w - lw) / 2, y), l, fh, INK, lang)
        y += lh
    fs = font(lang, round(base * (0.022 if single_line else 0.037)), 500)
    # tall scripts (Arabic, Devanagari, CJK) need more room under the headline
    y += base * (0.024 if face_for(lang) in (FACE["latin"], FACE["ru"]) else 0.042)
    sh = fs.size * (1.32 if face_for(lang) in (FACE["latin"], FACE["ru"]) else 1.5)
    for l in wrap(d, sub, fs, max_w * (1 if single_line else 0.9), lang):
        lw = text_w(d, l, fs, lang)
        draw_text(d, ((w - lw) / 2, y), l, fs, SUB, lang)
        y += sh
    return y


def compose(target: str, lang: str, screen: str, raw: Image.Image) -> Image.Image:
    w, h, kind, _ = TARGETS[target]
    canvas = ground(w, h)
    eyebrow, head, sub = CAPTIONS[lang][screen]
    chips = CHIPS[lang][screen]
    if target == "mac" and screen in CHIPS[lang].get("_mac", {}):
        chips = CHIPS[lang]["_mac"][screen]
    self_name = SELF[target]
    chips = [(t.replace("{self}", self_name), s.replace("{self}", self_name)) for t, s in chips]
    kinds = SCREENS[screen]

    if kind == "mac":
        base = h * 1.0
        y = captions_block(canvas, lang, eyebrow, head, sub, base, h * 0.06, w * 0.8, single_line=True)
        win = mac_window(raw, round(w * 0.64))
        wy = round(y + h * 0.035)
        sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        wx = (w - win.width) // 2
        ImageDraw.Draw(sh).rounded_rectangle((wx, wy + h * 0.02, wx + win.width, wy + win.height + h * 0.02), radius=24, fill=(0, 0, 0, 170))
        canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(h * 0.03)))
        canvas.alpha_composite(win, (wx, wy))
        ya, yb = CHIP_Y[screen]
        anchors = [(wx - base * 0.06, wy + win.height * (ya + 0.1), -2.5), (wx + win.width + base * 0.06, wy + win.height * (yb + 0.1), 2.0)]
        chip_base = base * 0.9
    else:
        tablet = kind in ("ipad", "android_tablet")
        base = w * (0.62 if tablet else 1.0)
        y = captions_block(canvas, lang, eyebrow, head, sub, base, h * (0.05 if tablet else 0.058), w * (0.82 if tablet else 0.86))
        dw = round(w * (0.8 if tablet else 0.86))
        body, inset = device(framed_screen(raw, kind), kind, dw)
        # every screenshot of a set starts its device at the same height,
        # unless a long caption needs more room
        dx, dy = (w - dw) // 2, round(max(h * (0.235 if tablet else 0.262), y + base * 0.05))
        sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle((dx, dy + base * 0.03, dx + dw, dy + body.height), radius=dw * 0.12, fill=(0, 0, 0, 160))
        canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(base * 0.05)))
        canvas.alpha_composite(body, (dx, dy))
        screen_h = body.height - 2 * inset
        ya, yb = CHIP_Y[screen]
        if tablet:  # the UI sits in the top part of a tablet screen
            ya, yb = ya * 0.75, yb * 0.75
        anchors = [(dx - base * 0.03, dy + inset + screen_h * ya, -2.5), (dx + dw + base * 0.03, dy + inset + screen_h * yb, 2.0)]
        chip_base = base

    for i, ((title, subline), (gk, col)) in enumerate(zip(chips, kinds)):
        c = chip(title, subline, gk, col, chip_base, lang)
        ax, ay, ang = anchors[i]
        c = c.rotate(ang, resample=Image.BICUBIC, expand=True)
        # chip 0 hangs over the left edge, chip 1 over the right; both stay on the canvas
        x = ax - c.width * 0.32 if i == 0 else ax - c.width * 0.68
        x = min(max(x, -c.width * 0.02), w - c.width * 0.98)
        canvas.alpha_composite(c, (round(x), round(ay - c.height / 2)))
    return canvas.convert("RGB")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--lang", action="append", help="default: every language that has raw captures")
    ap.add_argument("--target", action="append", help="default: every target that has raw captures")
    args = ap.parse_args()
    raw_root, out_root = pathlib.Path(args.raw), pathlib.Path(args.out)
    written = 0
    for target, (_, _, _, preset) in TARGETS.items():
        if args.target and target not in args.target:
            continue
        pdir = raw_root / preset
        if not pdir.is_dir():
            continue
        for ldir in sorted(p for p in pdir.iterdir() if p.is_dir()):
            lang = ldir.name
            if args.lang and lang not in args.lang:
                continue
            if lang not in CAPTIONS:
                print(f"no captions for {lang}, skipped")
                continue
            out = out_root / lang / target
            out.mkdir(parents=True, exist_ok=True)
            for png in sorted(ldir.glob("*.png")):
                screen = png.stem.split("_", 1)[1]
                im = compose(target, lang, screen, Image.open(png))
                im.save(out / png.name, optimize=True)
                written += 1
            print(f"{target} {lang}: {out}")
    print(f"{written} screenshots written")
    return 0


if __name__ == "__main__":
    sys.exit(main())

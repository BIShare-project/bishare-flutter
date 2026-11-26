#!/usr/bin/env python3
"""Microsoft Store screenshots in every app language, 1920x1080.

The same layout as compose.py (the English set), with the captions written by
hand per language in store/screens/captions.py and the caption faces of
store/screens/frame.py, so Arabic, Hindi and CJK draw with real glyphs.

    BISHARE_SHOTS_DIR=<raw> BISHARE_SHOTS_LOCALES=<lang> \\
      BISHARE_SHOTS_PRESETS=windows_store \\
      BISHARE_SHOTS_ONLY=1_share,2_inbox,3_link,4_drive,5_settings \\
      flutter test test/preview/store_screenshots_test.dart
    python3 store/screenshots/compose_l10n.py <raw> [lang ...]

Reads <raw>/windows_store/<lang>/*.png, writes windows/<lang>/0N-*.png.
"""

import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "screens"))
from captions import CAPTIONS  # noqa: E402
from frame import font  # noqa: E402

W, H = 1920, 1080
BG_TOP, BG_BOT = (2, 8, 23), (8, 17, 40)
ACCENT = (59, 130, 246)

# raw file keyword -> (caption key, output name)
SHOTS = [
    ("share", "share", "01-send.png"),
    ("inbox", "inbox", "02-inbox.png"),
    ("link", "link", "03-secure-link.png"),
    ("drive", "drive", "04-drive.png"),
    ("settings", "settings", "05-settings.png"),
]
LANGS = ["en", "id", "ar", "de", "es", "fr", "hi", "ja", "ko", "pt-BR", "ru", "zh-Hans", "zh-Hant"]


def rounded_shadow(shot, radius=18):
    w, h = shot.size
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius, fill=255)
    card = Image.new("RGBA", (w, h))
    card.paste(shot, (0, 0))
    card.putalpha(mask)
    ImageDraw.Draw(card).rounded_rectangle([0, 0, w - 1, h - 1], radius, outline=(255, 255, 255, 28), width=1)
    pad = 60
    layer = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    sh = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([pad, pad + 14, pad + w, pad + h + 14], radius + 6, fill=(0, 0, 0, 190))
    layer.alpha_composite(sh.filter(ImageFilter.GaussianBlur(34)))
    layer.alpha_composite(card, (pad, pad))
    return layer


def canvas():
    im = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(im)
    for y in range(H):
        t = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOT)))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([W // 2 - 620, -420, W // 2 + 620, 380], fill=ACCENT + (46,))
    im = Image.alpha_composite(im.convert("RGBA"), glow.filter(ImageFilter.GaussianBlur(150)))
    return im.convert("RGB")


def fitted(lang, text, size, weight, max_w):
    """The caption font at `size`, shrunk until `text` fits `max_w`."""
    while True:
        f = font(lang, size, weight)
        x0, _, x1, _ = ImageDraw.Draw(Image.new("RGB", (1, 1))).textbbox((0, 0), text, font=f)
        if x1 - x0 <= max_w or size <= 18:
            return f
        size -= 2


def centred(d, y, text, f, fill, lang):
    """Draw `text` centred at `y`; return the y of its lowest ink."""
    rtl = "rtl" if lang == "ar" else None
    x0, _, x1, y1 = d.textbbox((0, 0), text, font=f, direction=rtl)
    d.text(((W - (x1 - x0)) // 2 - x0, y), text, font=f, fill=fill, direction=rtl)
    return y + y1


def trim_dead_space(shot, keep_left=236):
    shot = shot.crop((2, 2, shot.width - 2, shot.height - 2))
    px = shot.load()
    bg = px[shot.width - 30, shot.height - 30]
    last = shot.height
    for y in range(shot.height - 1, -1, -1):
        if any(sum(abs(a - b) for a, b in zip(px[x, y], bg)) > 24 for x in range(keep_left, shot.width - 26, 3)):
            last = y
            break
    bottom = min(shot.height, last + 44)
    return shot.crop((0, 0, shot.width, bottom)) if bottom < shot.height - 8 else shot


def build(raw_png, lang, key, out):
    _, head, sub = CAPTIONS[lang][key]
    # one line on a desktop canvas; Chinese and Japanese take no space between
    head = head.replace("\n", "" if lang in ("ja", "zh-Hans", "zh-Hant") else " ")
    shot = trim_dead_space(Image.open(raw_png).convert("RGB"))
    scale = min(1.46, (H - 290) / shot.height)
    shot = shot.resize((round(shot.width * scale), round(shot.height * scale)), Image.LANCZOS)
    im = canvas()
    d = ImageDraw.Draw(im)
    bottom = centred(d, 62, head, fitted(lang, head, 52, 600, W - 160), (245, 248, 255), lang)
    # Arabic and Devanagari ink reaches lower than Latin: keep a clear gap
    centred(d, max(136, bottom + 18), sub, fitted(lang, sub, 27, 400, W - 160), (150, 168, 200), lang)
    card = rounded_shadow(shot)
    top = 196
    y = top + (H - top - card.height) // 2
    im.paste(card, ((W - card.width) // 2, max(top - 52, y)), card)
    path = HERE / "windows" / lang / out
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, "PNG")
    return path


def main():
    raw = Path(sys.argv[1])
    langs = sys.argv[2:] or LANGS
    for lang in langs:
        src = raw / "windows_store" / lang
        files = sorted(src.glob("*.png"))
        for word, key, out in SHOTS:
            hit = [p for p in files if word in p.stem]
            if not hit:
                print(f"!! {lang}: no raw shot for {word}")
                continue
            p = build(hit[0], lang, key, out)
            print(f"  {lang}/{out}  {os.path.getsize(p) // 1024} KB")


if __name__ == "__main__":
    main()

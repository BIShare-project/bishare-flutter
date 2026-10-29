#!/usr/bin/env python3
"""App Store creative assets (App Store Connect Help, "Creative assets
specifications"): the search results image (3:2, 3840x2560) and the product
page header (21:9, 3840x1646), one per language, built from the iPhone raw
captures of the store screenshot test and the Send caption.

The picture is the app in one glance: two iPhones, photos flying from the
sender to the receiver along a lit arc. Apple's asset best practices apply:
the purpose obvious at a glance, a short phrase, legible text, no website
addresses, no other platforms.

  python3 store/screens/creative.py --raw <out>/_raw --out <out> [--lang en ...]

writes <out>/<lang>/creative/search_3840x2560.png and header_3840x1646.png.
"""
from __future__ import annotations

import argparse
import math
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFilter

HERE = pathlib.Path(__file__).parent
sys.path.insert(0, str(HERE))
from frame import (  # noqa: E402
    CAPTIONS,
    CHIPS,
    EYEBROW,
    INK,
    SCREENS,
    SUB,
    chip,
    device,
    draw_text,
    font,
    framed_screen,
    ground,
    text_w,
    wrap,
)

SIZES = {"search": (3840, 2560), "header": (3840, 1646)}
ICON = HERE.parent.parent / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"
PHOTOS = sorted((HERE / "photos").glob("*.jpg"))


def rounded(im: Image.Image, size: int, radius: float) -> Image.Image:
    im = im.convert("RGBA").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    return out


def phone(raw: Image.Image, width: int, angle: float) -> Image.Image:
    """An iPhone around a capture, with a soft shadow, turned by `angle`."""
    body, _ = device(framed_screen(raw, "iphone"), "iphone", width)
    pad = round(width * 0.14)
    layer = Image.new("RGBA", (body.width + pad * 2, body.height + pad * 2), (0, 0, 0, 0))
    sh = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        (pad, pad + width * 0.05, pad + body.width, pad + body.height), radius=width * 0.13, fill=(0, 0, 0, 190)
    )
    layer.alpha_composite(sh.filter(ImageFilter.GaussianBlur(width * 0.07)))
    layer.alpha_composite(body, (pad, pad))
    return layer.rotate(angle, resample=Image.BICUBIC, expand=True)


def text_block(lang: str, w: int, base: float, align_right: bool) -> Image.Image:
    """App icon and name, then the headline and the line under it, aligned
    to the reading side."""
    _, head, sub = CAPTIONS[lang]["share"]
    im = Image.new("RGBA", (w, round(base * 1.2)), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    def x_for(width: float) -> float:
        return w - width if align_right else 0

    # icon + name
    isz = round(base * 0.1)
    icon = rounded(Image.open(ICON), isz, isz * 0.225)
    fn = font(lang, round(base * 0.045), 700)
    name_w = text_w(d, "BIShare", fn, "en")
    row_w = isz + base * 0.025 + name_w
    x0 = x_for(row_w)
    im.alpha_composite(icon, (round(x0 if not align_right else x0 + name_w + base * 0.025), 0))
    nx = x0 + isz + base * 0.025 if not align_right else x0
    draw_text(d, (nx, isz / 2 - fn.size * 0.62), "BIShare", fn, EYEBROW, "en")
    y = isz + base * 0.07
    # headline: as large as fits, lines as written
    size = round(base * 0.13)
    parts = head.split("\n")
    while size > base * 0.06:
        fh = font(lang, size, 800)
        if all(text_w(d, p, fh, lang) <= w for p in parts):
            break
        size = round(size * 0.95)
    fh = font(lang, size, 800)
    lh = size * (1.08 if lang not in ("ar", "hi", "ja", "ko", "zh-Hans", "zh-Hant") else 1.25)
    for p in parts:
        draw_text(d, (x_for(text_w(d, p, fh, lang)), y), p, fh, INK, lang)
        y += lh
    y += base * 0.035
    fs = font(lang, round(base * 0.042), 500)
    for line in wrap(d, sub, fs, w, lang):
        draw_text(d, (x_for(text_w(d, line, fs, lang)), y), line, fs, SUB, lang)
        y += fs.size * 1.4
    return im.crop((0, 0, w, round(y + base * 0.02)))


def arc_points(a: tuple[float, float], b: tuple[float, float], lift: float, n: int = 120) -> list[tuple[float, float]]:
    """A quadratic arc from a to b, bowed up by `lift`."""
    cx, cy = (a[0] + b[0]) / 2, min(a[1], b[1]) - lift
    pts = []
    for i in range(n + 1):
        t = i / n
        x = (1 - t) ** 2 * a[0] + 2 * (1 - t) * t * cx + t * t * b[0]
        y = (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * cy + t * t * b[1]
        pts.append((x, y))
    return pts


def transfer(canvas: Image.Image, pts: list[tuple[float, float]], tile: int) -> None:
    """The lit arc, then three photos riding it, the nearest the largest."""
    w = canvas.width
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.line(pts, fill=(120, 190, 255, 200), width=round(tile * 0.16), joint="curve")
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(tile * 0.12)))
    d = ImageDraw.Draw(canvas)
    # a dashed core: data on its way
    for i in range(0, len(pts) - 1, 4):
        d.line([pts[i], pts[i + 2]], fill=(235, 245, 255, 255), width=max(3, round(tile * 0.03)))
    for k, (t, scale, ang) in enumerate(((0.28, 1.0, -10), (0.5, 0.86, 4), (0.72, 0.72, 12))):
        x, y = pts[round(t * (len(pts) - 1))]
        s = round(tile * scale)
        photo = rounded(Image.open(PHOTOS[(k * 5) % len(PHOTOS)]), s, s * 0.16)
        frame = Image.new("RGBA", (s + 16, s + 16), (0, 0, 0, 0))
        ImageDraw.Draw(frame).rounded_rectangle((0, 0, s + 15, s + 15), radius=s * 0.18, fill=(255, 255, 255, 255))
        frame.alpha_composite(photo, (8, 8))
        pad = round(s * 0.25)
        lay = Image.new("RGBA", (frame.width + pad * 2, frame.height + pad * 2), (0, 0, 0, 0))
        sh = Image.new("RGBA", lay.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle((pad, pad + s * 0.06, pad + frame.width, pad + frame.height), radius=s * 0.18, fill=(0, 0, 0, 150))
        lay.alpha_composite(sh.filter(ImageFilter.GaussianBlur(s * 0.08)))
        lay.alpha_composite(frame, (pad, pad))
        lay = lay.rotate(ang, resample=Image.BICUBIC, expand=True)
        canvas.alpha_composite(lay, (round(x - lay.width / 2), round(y - lay.height / 2)))


def build(kind: str, lang: str, shots: dict[str, Image.Image]) -> Image.Image:
    W, H = SIZES[kind]
    rtl = lang == "ar"
    canvas = ground(W, H).convert("RGBA")

    def X(x: float) -> float:
        return W - x if rtl else x

    if kind == "search":
        base, pw, text_w_, tx, ty = W * 0.62, round(W * 0.19), round(W * 0.4), W * 0.05, H * 0.3
        send_c, recv_c, send_top, recv_top, lift = (0.6, 0.875), None, H * 0.18, H * 0.25, H * 0.2
    else:
        base, pw, text_w_, tx, ty = W * 0.5, round(W * 0.15), round(W * 0.36), W * 0.05, H * 0.24
        send_c, recv_c, send_top, recv_top, lift = (0.55, 0.86), None, H * 0.12, H * 0.2, H * 0.18
    # a soft light behind the phones
    light = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    r = H * 0.5
    lx = X(W * 0.73)
    ImageDraw.Draw(light).ellipse((lx - r, H * 0.5 - r, lx + r, H * 0.5 + r), fill=(110, 170, 255, 90))
    canvas.alpha_composite(light.filter(ImageFilter.GaussianBlur(r * 0.5)))
    # phones: the sender in front, the receiver a little behind
    recv = phone(shots["inbox"], pw, -7 if rtl else 7)
    send = phone(shots["share"], pw, 7 if rtl else -7)
    rx, sx = X(W * send_c[1]) - recv.width / 2, X(W * send_c[0]) - send.width / 2
    canvas.alpha_composite(recv, (round(rx), round(recv_top)))
    canvas.alpha_composite(send, (round(sx), round(send_top)))
    # photos fly from the sender to the receiver, over both
    a = (X(W * send_c[0]) + (pw * 0.32 if not rtl else -pw * 0.32), send_top + send.height * 0.3)
    b = (X(W * send_c[1]) - (pw * 0.3 if not rtl else -pw * 0.3), recv_top + recv.height * 0.24)
    pts = arc_points(a, b, lift)
    transfer(canvas, pts, round(pw * 0.42))
    # badges: "sent" over the arc, "verified" on the receiver
    (st, ss), (vt, vs) = CHIPS[lang]["share"][1], CHIPS[lang]["inbox"][1]
    cb = base * 0.95
    c1 = chip(st, ss, SCREENS["share"][1][0], SCREENS["share"][1][1], cb, lang)
    top = min(p[1] for p in pts)
    canvas.alpha_composite(c1, (round((a[0] + b[0]) / 2 - c1.width / 2), round(top - c1.height * 1.15)))
    c2 = chip(vt, vs, SCREENS["inbox"][1][0], SCREENS["inbox"][1][1], cb, lang)
    cx2 = X(W * send_c[1]) + (pw * 0.15 if not rtl else -pw * 0.15) - c2.width / 2
    canvas.alpha_composite(c2, (round(min(max(cx2, W * 0.02), W * 0.98 - c2.width)), round(recv_top + recv.height * 0.62)))
    # text on the reading side
    tb = text_block(lang, text_w_, base, rtl)
    canvas.alpha_composite(tb, (round(W - tx - tb.width) if rtl else round(tx), round((H - tb.height) / 2)))
    return canvas.convert("RGB")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--lang", action="append")
    args = ap.parse_args()
    raw_root, out_root = pathlib.Path(args.raw) / "ios_phone", pathlib.Path(args.out)
    written = 0
    for ldir in sorted(p for p in raw_root.iterdir() if p.is_dir()):
        lang = ldir.name
        if args.lang and lang not in args.lang:
            continue
        shots = {png.stem.split("_", 1)[1]: Image.open(png) for png in ldir.glob("*.png")}
        if not {"share", "inbox"} <= shots.keys():
            print(f"{lang}: missing captures, skipped")
            continue
        out = out_root / lang / "creative"
        out.mkdir(parents=True, exist_ok=True)
        for kind, (w, h) in SIZES.items():
            build(kind, lang, shots).save(out / f"{kind}_{w}x{h}.png", optimize=True)
            written += 1
    print(f"{written} creative assets written")
    return 0


if __name__ == "__main__":
    sys.exit(main())

from PIL import Image, ImageDraw, ImageFilter, ImageFont
import os
SP = os.path.dirname(os.path.abspath(__file__))
W, H = 1920, 1080
BG_TOP, BG_BOT = (2, 8, 23), (8, 17, 40)
ACCENT = (59, 130, 246)

def font(size, weight="Regular"):
    f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)
    try: f.set_variation_by_name(weight)
    except Exception: pass
    return f

def rounded_shadow(shot, radius=18):
    """App capture with rounded corners, hairline border and a soft shadow."""
    w, h = shot.size
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w-1, h-1], radius, fill=255)
    card = Image.new("RGBA", (w, h)); card.paste(shot, (0, 0)); card.putalpha(mask)
    d = ImageDraw.Draw(card)
    d.rounded_rectangle([0, 0, w-1, h-1], radius, outline=(255, 255, 255, 28), width=1)
    pad = 60
    layer = Image.new("RGBA", (w+pad*2, h+pad*2), (0, 0, 0, 0))
    sh = Image.new("RGBA", (w+pad*2, h+pad*2), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([pad, pad+14, pad+w, pad+h+14], radius+6, fill=(0, 0, 0, 190))
    layer.alpha_composite(sh.filter(ImageFilter.GaussianBlur(34)))
    layer.alpha_composite(card, (pad, pad))
    return layer

def canvas():
    im = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(im)
    for y in range(H):                                   # vertical gradient
        t = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(round(a+(b-a)*t) for a, b in zip(BG_TOP, BG_BOT)))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))       # soft brand glow, top centre
    ImageDraw.Draw(glow).ellipse([W//2-620, -420, W//2+620, 380], fill=ACCENT+(46,))
    im = Image.alpha_composite(im.convert("RGBA"), glow.filter(ImageFilter.GaussianBlur(150)))
    return im.convert("RGB")

def centred(d, y, text, f, fill):
    x0, _, x1, _ = d.textbbox((0, 0), text, font=f)
    d.text(((W-(x1-x0))//2, y), text, font=f, fill=fill)

def trim_dead_space(shot, keep_left=236):
    """Drop empty background below the last row of content (right pane only —
    the nav rail runs the full height). Nothing inside the UI is cut."""
    shot = shot.crop((2, 2, shot.width-2, shot.height-2))  # drop the window's own edge
    px = shot.load()
    bg = px[shot.width-30, shot.height-30]
    last = shot.height
    for y in range(shot.height-1, -1, -1):
        row_has_content = any(
            sum(abs(a-b) for a, b in zip(px[x, y], bg)) > 24
            for x in range(keep_left, shot.width-26, 3))
        if row_has_content:
            last = y
            break
    bottom = min(shot.height, last + 44)
    return shot.crop((0, 0, shot.width, bottom)) if bottom < shot.height - 8 else shot

def build(src, head, sub, out, scale=1.28, trim=False):
    shot = Image.open(os.path.join(SP, "shots", src)).convert("RGB")
    if trim:
        shot = trim_dead_space(shot)
        scale = min(1.46, (H - 290) / shot.height)
    shot = shot.resize((round(shot.width*scale), round(shot.height*scale)), Image.LANCZOS)
    im = canvas()
    d = ImageDraw.Draw(im)
    centred(d, 66, head, font(52, "Semibold"), (245, 248, 255))
    centred(d, 136, sub, font(27), (150, 168, 200))
    card = rounded_shadow(shot)
    # centre the card in the space left under the caption
    top, bottom = 196, H
    y = top + (bottom - top - card.height)//2
    im.paste(card, ((W-card.width)//2, max(top-52, y)), card)
    path = os.path.join(SP, "store", out)
    im.save(path, "PNG")
    print(f"  {out}  {im.size[0]}x{im.size[1]}  {os.path.getsize(path)//1024} KB")

build("J-fix-verified.png", "Send anything, to anyone",
      "An encrypted link or QR — up to 100 GB, no account, expires in 24 hours",
      "01-secure-link.png", trim=True)
build("K-sheet-mid.png", "Encrypted before it leaves your PC",
      "The key travels inside the link. The relay only ever stores what it cannot read.",
      "02-encryption.png")
build("B-rooms.png", "Rooms: one code, several devices",
      "Over your own Wi-Fi, or across the country",
      "03-rooms.png", trim=True)
build("I-devices.png", "Windows, iPhone, Android, Mac and Linux",
      "One app on every device you own — and none needed on theirs",
      "04-devices.png", trim=True)
build("C-settings.png", "Yours to set up",
      "Name, theme, accent colours and 13 languages",
      "05-settings.png")

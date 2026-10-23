#!/usr/bin/env python3
"""Frame raw simulator captures into captioned App Store screenshots.

Output size == input size (each capture is already the exact App Store
size for its device class), opaque PNG.

usage: /usr/bin/python3 frame.py <raw-dir> <out-dir>
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

RAW, OUT = Path(sys.argv[1]), Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)

FONT = '/System/Library/Fonts/SFNSRounded.ttf'
TOP, BOTTOM = (6, 58, 74), (3, 28, 38)                    # the icon's deep teal
ACCENT = [(92, 184, 92), (236, 176, 72), (222, 112, 70)]  # grass, ochre, terracotta

# Titles use explicit line breaks (portrait); landscape joins them on one line.
CAPTIONS = {
    'list': ('Know when your\ntrails are ridable', 'Every saved trail, rated and forecast'),
    'detail': ('Hero dirt?\nGo ride.', 'Soaked, Muddy, Hero Dirt, Dry or Dusty'),
    'trend': ('Plan the\nweek ahead', 'See when trails dry out and when rain hits'),
    'rainmap': ('See where\nit rained', 'Rain map for the last 1, 2, 3 or 7 days'),
    'dark-list': ('Made for riders,\nday or night', 'Free, no ads, no account'),
    'split': ('Your trails,\nside by side', 'Built for the big screen on iPhone Duo'),
    'map': ('Every trail\non the map', 'Pins colored by trail condition'),
}

# App Store sets: (glob prefix, output folder, order)
SETS = [
    ('p17-', 'iphone-6.3', ['1-list', '2-detail', '3-trend', '4-rainmap', '5-dark-list']),
    ('pm-', 'iphone-6.9', ['1-list', '2-detail', '3-trend', '4-rainmap', '5-dark-list']),
    ('duo-outer-', 'iphone-duo-outer', ['1-list', '2-detail', '3-trend', '4-dark-list']),
    ('duo-inner-tall-', 'iphone-duo-inner-portrait', ['1-list']),
    ('duo-inner-wide-', 'iphone-duo-inner-landscape', ['1-split', '2-map']),
]


def font(size, weight=b'Bold'):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def wrap(text, f, max_w, draw):
    words, lines, cur = text.split(), [], ''
    for w in words:
        trial = (cur + ' ' + w).strip()
        if draw.textlength(trial, font=f) <= max_w or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    lines.append(cur)
    return lines


def gradient(w, h):
    bg = Image.new('RGB', (w, h))
    d = ImageDraw.Draw(bg)
    for y in range(h):
        t = y / h
        d.line([(0, y), (w, y)], fill=tuple(int(TOP[k] * (1 - t) + BOTTOM[k] * t) for k in range(3)))
    return bg


def frame(src, title, sub):
    shot = Image.open(src).convert('RGB')
    W, H = shot.size
    landscape = W > H
    bg = gradient(W, H)
    d = ImageDraw.Draw(bg)
    u = min(W, H) / 1320  # scale unit

    # Caption block.
    if landscape:  # one-line caption, smaller, so the screenshot stays big
        u *= 0.72
        title = title.replace('\n', ' ')
    tf, sf = font(int(118 * u)), font(int(50 * u), b'Medium')
    max_w = W * 0.9
    title_lines = [l for part in title.split('\n') for l in wrap(part, tf, max_w, d)]
    top = int(H * 0.05)
    stripe_w, stripe_gap = int(72 * u), int(12 * u)
    sx = W / 2 - (3 * stripe_w + 2 * stripe_gap) / 2
    for k, c in enumerate(ACCENT):
        x = sx + k * (stripe_w + stripe_gap)
        d.rounded_rectangle([x, top, x + stripe_w, top + int(16 * u)], radius=int(8 * u), fill=c)
    y = top + int(70 * u)
    for line in title_lines:
        tw = d.textlength(line, font=tf)
        d.text(((W - tw) / 2, y), line, font=tf, fill=(255, 255, 255))
        y += int(tf.size * 1.17)
    sw = d.textlength(sub, font=sf)
    d.text(((W - sw) / 2, y + int(14 * u)), sub, font=sf, fill=(190, 222, 228))
    caption_bottom = y + int(14 * u) + sf.size + int(70 * u)

    # Screenshot below the caption, scaled to fit, rounded with a bezel.
    avail_h = H - caption_bottom - int(40 * u)
    scale = min(avail_h / H, (W * 0.86) / W)
    sw_, sh_ = int(W * scale), int(H * scale)
    img = shot.resize((sw_, sh_), Image.LANCZOS)
    r = int(min(sw_, sh_) * 0.075)
    m = Image.new('L', (sw_ * 2, sh_ * 2), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, sw_ * 2 - 1, sh_ * 2 - 1], radius=r * 2, fill=255)
    m = m.resize((sw_, sh_), Image.LANCZOS)
    x0, y0 = (W - sw_) // 2, caption_bottom
    sh = Image.new('L', (W, H), 0)
    sh.paste(m, (x0, y0 + int(24 * u)))
    sh = sh.filter(ImageFilter.GaussianBlur(40 * u)).point(lambda v: int(v * 0.55))
    bg = Image.composite(Image.new('RGB', (W, H), (0, 0, 0)), bg, sh)
    pad = max(6, int(12 * u))
    bez = Image.new('L', (sw_ + 2 * pad, sh_ + 2 * pad), 0)
    ImageDraw.Draw(bez).rounded_rectangle([0, 0, sw_ + 2 * pad - 1, sh_ + 2 * pad - 1], radius=r + pad, fill=255)
    bg.paste(Image.new('RGB', bez.size, (18, 18, 20)), (x0 - pad, y0 - pad), bez)
    bg.paste(img, (x0, y0), m)
    return bg


def main():
    for prefix, folder, order in SETS:
        for i, name in enumerate(order, 1):
            src = RAW / f'{prefix}{name}.png'
            if not src.exists():
                print('missing', src.name)
                continue
            key = name.split('-', 1)[1]
            out = frame(src, *CAPTIONS[key])
            dest = OUT / folder / f'{i:02d}-{key}.png'
            dest.parent.mkdir(parents=True, exist_ok=True)
            out.save(dest, optimize=True)
            print(dest.relative_to(OUT), out.size)


if __name__ == '__main__':
    main()

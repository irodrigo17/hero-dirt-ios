#!/usr/bin/env python3
"""App Store Connect creative assets for Hero Dirt.

Generates the product page header (21:9), search results (3:2) and the
universal 16:9 creative asset, with all key artwork inside Apple's
published "art safe area" (measured from Apple's templates). Opaque PNGs,
no alpha.

usage: /usr/bin/python3 make_creative_assets.py <icon-1024.png> <list-screenshot.png> <out-dir>
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ICON, LIST_SHOT, OUT = sys.argv[1], sys.argv[2], Path(sys.argv[3])
OUT.mkdir(parents=True, exist_ok=True)

FONT = '/System/Library/Fonts/SFNSRounded.ttf'
TITLE = 'Hero Dirt'
TAGLINE = 'Know when your trails are ridable'

# Safe areas (x0, y0, x1, y1) measured from Apple's static templates.
SPECS = {
    'header-21x9-3840x1646': ((3840, 1646), (1097, 493, 2742, 1153)),
    'search-results-3x2-3840x2560': ((3840, 2560), (836, 765, 3003, 1794)),
    'universal-16x9-5244x2950': ((5244, 2950), (1921, 660, 3322, 1621)),
}

SKY_TOP = np.array([10, 58, 72])
SKY_BOTTOM = np.array([4, 26, 34])
LAYERS = [  # top to bottom: grass, ochre, terracotta, sienna (the icon's strata)
    ((92, 184, 92), (62, 145, 66)),
    ((236, 176, 72), (214, 146, 52)),
    ((222, 112, 70), (190, 88, 54)),
    ((140, 66, 40), (104, 46, 28)),
]


def font(size, weight=b'Bold'):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def background(w, h, ground_top, keep_clear=None):
    """Teal sky with a soft glow and layered, wavy soil strata at the bottom."""
    y = np.linspace(0, 1, h)[:, None, None]
    img = SKY_TOP * (1 - y) + SKY_BOTTOM * y
    img = np.repeat(img, w, axis=1).astype(float)

    # Soft glow behind the center.
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot((xx - w / 2) / (w * 0.45), (yy - h * 0.42) / (h * 0.55))
    glow = np.clip(1 - r, 0, 1)[..., None] ** 2
    img = img + glow * np.array([28, 60, 64])

    canvas = Image.fromarray(img.clip(0, 255).astype(np.uint8))
    draw = ImageDraw.Draw(canvas)

    # Faint sparkles in the sky.
    rng = np.random.default_rng(7)
    for _ in range(int(w * h / 90000)):
        sx, sy = rng.uniform(0, w), rng.uniform(0, ground_top * 0.9)
        if keep_clear:  # no sparkles behind the text/artwork
            cx0, cy0, cx1, cy1 = keep_clear
            pad = w * 0.02
            if cx0 - pad < sx < cx1 + pad and cy0 - pad < sy < cy1 + pad:
                continue
        s = rng.uniform(1.5, 4.5) * w / 3840
        a = int(rng.uniform(40, 130))
        draw.ellipse([sx - s, sy - s, sx + s, sy + s], fill=(255, 255, 255, a))

    # Strata: each layer is a smooth wave; drawn back to front.
    band = (h - ground_top) / (len(LAYERS) + 0.4)
    xs = np.arange(0, w + 8, 8)
    for i, (top_c, bot_c) in enumerate(LAYERS):
        phase = i * 1.3
        amp = band * 0.38
        base = ground_top + i * band
        wave = (np.sin(xs / w * 2 * math.pi * 1.15 + phase) * amp
                + np.sin(xs / w * 2 * math.pi * 2.7 + phase * 2.1) * amp * 0.35)
        top = base + wave
        mask = Image.new('L', (w, h), 0)
        ImageDraw.Draw(mask).polygon(
            [(0, h)] + [(float(x), float(t)) for x, t in zip(xs, top)] + [(w, h)], fill=255
        )
        mask = mask.filter(ImageFilter.GaussianBlur(1.2 * w / 3840))
        g = np.linspace(0, 1, h)[:, None, None]
        layer = np.array(top_c) * (1 - g) + np.array(bot_c) * g
        layer = Image.fromarray(np.repeat(layer, w, axis=1).clip(0, 255).astype(np.uint8))
        canvas.paste(layer, (0, 0), mask)
        # highlight on the crest
        hl = Image.new('L', (w, h), 0)
        ImageDraw.Draw(hl).line([(float(x), float(t) + 3) for x, t in zip(xs, top)],
                                fill=90, width=max(2, int(6 * w / 3840)))
        hl = hl.filter(ImageFilter.GaussianBlur(3 * w / 3840))
        canvas.paste(Image.new('RGB', (w, h), (255, 255, 255)), (0, 0), hl)
    return canvas


def rounded(im, radius_frac=0.2237):
    w, h = im.size
    m = Image.new('L', (w * 4, h * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w * 4 - 1, h * 4 - 1], radius=int(w * 4 * radius_frac), fill=255)
    out = im.convert('RGBA')
    out.putalpha(m.resize((w, h), Image.LANCZOS))
    return out


def shadow_paste(canvas, img, xy, blur, offset, opacity=0.45):
    """Paste RGBA `img` with a soft drop shadow."""
    x, y = xy
    sh = Image.new('L', canvas.size, 0)
    sh.paste(img.getchannel('A'), (x, y + offset))
    sh = sh.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * opacity))
    canvas.paste(Image.new('RGB', canvas.size, (0, 0, 0)), (0, 0), sh)
    canvas.paste(img, (x, y), img)


def fit_font(text, max_w, start, weight=b'Bold'):
    size = start
    while size > 10:
        f = font(size, weight)
        if ImageDraw.Draw(Image.new('RGB', (1, 1))).textlength(text, font=f) <= max_w:
            return f
        size -= 2
    return font(size, weight)


def ui_card(target_w):
    """Crop of the real My Trails list (two trail cards) as a rounded glass card."""
    shot = Image.open(LIST_SHOT).convert('RGB')
    sw = shot.width
    # The first two trail cards (between list separators), on white with
    # a little padding. Fractions of the screenshot width so it works for
    # any capture size.
    crop = shot.crop((0, int(sw * 0.405), sw, int(sw * 1.008)))
    pad = int(sw * 0.03)
    card = Image.new('RGB', (crop.width, crop.height + 2 * pad), (255, 255, 255))
    card.paste(crop, (0, pad))
    scale = target_w / card.width
    card = card.resize((target_w, int(card.height * scale)), Image.LANCZOS)
    return rounded(card, radius_frac=0.06)


def lockup(canvas, safe, layout, icon):
    """Icon + title + tagline, laid out inside the safe area."""
    # Keep a small margin inside the safe area so nothing sits on its edge.
    m = int(min(safe[2] - safe[0], safe[3] - safe[1]) * 0.04)
    x0, y0, x1, y1 = safe[0] + m, safe[1] + m, safe[2] - m, safe[3] - m
    sw, sh = x1 - x0, y1 - y0
    d = ImageDraw.Draw(canvas)
    white, sub = (255, 255, 255), (198, 228, 232)

    if layout == 'row':  # icon left, text right (header)
        icon_s = int(sh * 0.78)
        gap = int(icon_s * 0.16)
        text_w = sw - icon_s - gap
        tf = fit_font(TITLE, text_w, int(sh * 0.34))
        lines = ['Know when your', 'trails are ridable']
        sf = fit_font(max(lines, key=len), text_w, int(sh * 0.15), b'Semibold')
        th = tf.size * 1.05 + 2 * sf.size * 1.2
        ix = x0
        iy = y0 + (sh - icon_s) // 2
        shadow_paste(canvas, rounded(icon.resize((icon_s, icon_s), Image.LANCZOS)), (ix, iy), icon_s * 0.06, int(icon_s * 0.04))
        tx = ix + icon_s + gap
        ty = y0 + (sh - th) / 2 - tf.size * 0.12
        d.text((tx, ty), TITLE, font=tf, fill=white)
        ty += tf.size * 1.12
        for line in lines:
            d.text((tx, ty), line, font=sf, fill=sub)
            ty += sf.size * 1.2

    elif layout == 'stack':  # icon above centered text (universal)
        icon_s = int(sh * 0.44)
        tf = fit_font(TITLE, sw * 0.9, int(sh * 0.17))
        sf = fit_font(TAGLINE, sw * 0.95, int(sh * 0.075), b'Semibold')
        gap1, gap2 = int(sh * 0.06), int(sh * 0.03)
        total = icon_s + gap1 + tf.size + gap2 + sf.size
        iy = y0 + (sh - total) // 2
        ix = x0 + (sw - icon_s) // 2
        shadow_paste(canvas, rounded(icon.resize((icon_s, icon_s), Image.LANCZOS)), (ix, iy), icon_s * 0.06, int(icon_s * 0.04))
        ty = iy + icon_s + gap1 - tf.size * 0.12
        tw = d.textlength(TITLE, font=tf)
        d.text((x0 + (sw - tw) / 2, ty), TITLE, font=tf, fill=white)
        ty += tf.size + gap2
        stw = d.textlength(TAGLINE, font=sf)
        d.text((x0 + (sw - stw) / 2, ty), TAGLINE, font=sf, fill=sub)

    elif layout == 'search':  # lockup left, real UI card right (search results)
        card_w = int(sw * 0.52)
        card = ui_card(card_w)
        if card.height > sh:
            card = ui_card(int(card_w * sh / card.height))
        cx = x1 - card.width
        cy = y0 + (sh - card.height) // 2
        shadow_paste(canvas, card, (cx, cy), card.width * 0.03, int(card.width * 0.02), 0.5)
        left_w = cx - x0 - int(sw * 0.05)
        icon_s = int(min(left_w * 0.42, sh * 0.34))
        tf = fit_font(TITLE, left_w, int(sh * 0.16))
        lines = ['Know when your', 'trails are ridable']
        sf = fit_font(max(lines, key=len), left_w, int(sh * 0.085), b'Semibold')
        total = icon_s + sh * 0.06 + tf.size * 1.1 + 2 * sf.size * 1.2
        ty = y0 + (sh - total) / 2
        shadow_paste(canvas, rounded(icon.resize((icon_s, icon_s), Image.LANCZOS)), (x0, int(ty)), icon_s * 0.06, int(icon_s * 0.04))
        ty += icon_s + sh * 0.06 - tf.size * 0.12
        d.text((x0, ty), TITLE, font=tf, fill=white)
        ty += tf.size * 1.12
        for line in lines:
            d.text((x0, ty), line, font=sf, fill=sub)
            ty += sf.size * 1.2


def main():
    icon = Image.open(ICON).convert('RGB')
    layouts = {
        'header-21x9-3840x1646': 'row',
        'search-results-3x2-3840x2560': 'search',
        'universal-16x9-5244x2950': 'stack',
    }
    for name, ((w, h), safe) in SPECS.items():
        ground_top = int(max(safe[3] + (h - safe[3]) * 0.25, h * 0.74))
        canvas = background(w, h, ground_top, keep_clear=safe)
        lockup(canvas, safe, layouts[name], icon)
        canvas = canvas.convert('RGB')  # no alpha (App Store requirement)
        canvas.save(OUT / f'{name}.png', optimize=True)
        # preview with the safe area outlined
        prev = canvas.copy()
        ImageDraw.Draw(prev).rectangle(safe, outline=(0, 255, 0), width=max(4, w // 600))
        prev.thumbnail((1600, 1600))
        prev.save(OUT / f'preview-{name}.png')
        print(name, canvas.size)


if __name__ == '__main__':
    main()

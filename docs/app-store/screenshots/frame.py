from PIL import Image, ImageDraw, ImageFont, ImageFilter
W, H = 1320, 2868
shots = [
    ('raw-1-list.png', 'Know when your\ntrails are ridable', 'Every saved trail, rated and forecast'),
    ('raw-2-hero-detail.png', 'Hero dirt?\nGo ride.', 'Soaked, Muddy, Hero Dirt, Dry or Dusty'),
    ('raw-3-trend.png', 'Plan the\nweek ahead', 'See when trails dry out and when rain hits'),
    ('raw-4-rainmap.png', 'See where\nit rained', 'Rain map for the last 1, 2, 3 or 7 days'),
    ('raw-6-dark-list.png', 'Made for riders,\nday or night', 'Free, no ads, no account'),
]
bold = '/System/Library/Fonts/SFNSRounded.ttf'
def font(size, weight='Bold'):
    f = ImageFont.truetype(bold, size)
    try: f.set_variation_by_name(weight)
    except Exception: pass
    return f
top_c, bot_c = (6, 58, 74), (3, 28, 38)   # deep teal from the drop icon
accent = [(76, 175, 80), (240, 170, 60), (226, 104, 64)]  # green, ochre, terracotta
for i, (src, title, sub) in enumerate(shots, 1):
    bg = Image.new('RGB', (W, H))
    d = ImageDraw.Draw(bg)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=tuple(int(top_c[k]*(1-t) + bot_c[k]*t) for k in range(3)))
    # three thin accent stripes (the drop's layers)
    for k, c in enumerate(accent):
        d.rounded_rectangle([W//2 - 120 + k*84, 150, W//2 - 120 + k*84 + 72, 166], radius=8, fill=c)
    tf = font(118); sf = font(50, 'Medium')
    y = 230
    for line in title.split('\n'):
        tw = d.textlength(line, font=tf); d.text(((W - tw)/2, y), line, font=tf, fill='white'); y += 138
    sw = d.textlength(sub, font=sf); d.text(((W - sw)/2, y + 18), sub, font=sf, fill=(190, 222, 228))
    # screenshot, scaled with rounded corners and shadow
    shot = Image.open(src).convert('RGB')
    scale = 0.80; sw_, sh_ = int(W*scale), int(H*scale)
    shot = shot.resize((sw_, sh_), Image.LANCZOS)
    r = 90
    m = Image.new('L', (sw_*2, sh_*2), 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, sw_*2-1, sh_*2-1], radius=r*2, fill=255)
    m = m.resize((sw_, sh_), Image.LANCZOS)
    x0, y0 = (W - sw_)//2, y + 130
    shadow = Image.new('L', (W, H), 0); shadow.paste(m, (x0, y0 + 24))
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    bg = Image.composite(Image.new('RGB', (W, H), (0, 0, 0)), bg, shadow.point(lambda a: int(a*0.55)))
    # thin bezel
    bez = Image.new('L', (sw_ + 24, sh_ + 24), 0)
    ImageDraw.Draw(bez).rounded_rectangle([0, 0, sw_ + 23, sh_ + 23], radius=r + 12, fill=255)
    bg.paste(Image.new('RGB', bez.size, (18, 18, 20)), (x0 - 12, y0 - 12), bez)
    bg.paste(shot, (x0, y0), m)
    bg.save(f'out/{i:02d}.png')
    print(i, bg.size)

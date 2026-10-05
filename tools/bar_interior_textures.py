#!/usr/bin/env python3
"""Paint the dive-bar interior textures (tools/bar_interior_tex/*.png).

Everything is drawn here in the same grimy, hand-painted look as the bar's outside: worn wood,
stained felt, cracked vinyl, a pressed-tin ceiling, neon signs, posters and liquor labels for
invented brands (Lumberjack is the game's own beer). Tiling textures are made seamless, and the
wood gets a matching normal map from its brightness.

usage: bar_interior_textures.py <out dir>
"""
import math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy.ndimage import gaussian_filter, sobel

OUT = sys.argv[1] if len(sys.argv) > 1 else 'tools/bar_interior_tex'
os.makedirs(OUT, exist_ok=True)
HERE = os.path.dirname(os.path.abspath(__file__))
FX = os.path.join(HERE, '..', 'assets', 'fx')
F_RYE = os.path.join(FX, 'Rye-Regular.ttf'); F_SLAB = os.path.join(FX, 'AlfaSlabOne-Regular.ttf'); F_ARCH = os.path.join(FX, 'Archivo.ttf')
F_POP = '/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf'; F_SCRIPT = '/usr/share/fonts/truetype/google-fonts/Lora-Italic-Variable.ttf'
rng = np.random.default_rng(7)

def save(a, name, mode='RGB'):
    """opaque textures go out as JPEG (smaller GLB), the ones with alpha as PNG"""
    a = np.clip(a, 0, 1)
    im = Image.fromarray((a * 255).astype(np.uint8), mode)
    if mode == 'RGB': im.save(os.path.join(OUT, name.replace('.png', '.jpg')), quality=90)
    else: im.save(os.path.join(OUT, name))
def save_im(im, name): im.convert('RGB').save(os.path.join(OUT, name.replace('.png', '.jpg')), quality=90)

def tnoise(shape, sigma, seed=None):
    """tileable smooth noise"""
    r = np.random.default_rng(seed).standard_normal(shape)
    n = gaussian_filter(r, sigma, mode='wrap'); return n / (np.abs(n).max() + 1e-9)

def normal_from(height, strength, name):
    gx = sobel(height, 1, mode='wrap'); gy = sobel(height, 0, mode='wrap')
    n = np.dstack([-gx * strength, gy * strength, np.ones_like(height)])     # OpenGL (green up)
    n /= np.linalg.norm(n, axis=2, keepdims=True); save(n * 0.5 + 0.5, name)

# ---------------------------------------------------------------- wood: planks with grain, wear and grime
def planks(S, n_planks, base, dark, along_x, seed, gaps=True, gloss_streak=False):
    r = np.random.default_rng(seed)
    y, x = np.mgrid[0:S, 0:S] / S
    u, v = (x, y) if along_x else (y, x)                 # u along the grain, v across planks
    pw = 1.0 / n_planks; k = np.floor(v / pw); fv = (v % pw) / pw
    img = np.zeros((S, S, 3)); h = np.zeros((S, S))
    tone = r.uniform(0.75, 1.15, n_planks)
    off = r.uniform(0, 1, n_planks)
    grain_n = tnoise((S, S), (S / 60, S / 3) if along_x else (S / 3, S / 60), seed + 1)
    for i in range(n_planks):
        m = k == i
        g = np.sin((v[m] * n_planks * 7 + grain_n[m] * 3.5 + off[i] * 9) * 6.0) * 0.5 + 0.5
        g = g ** 2.2
        c = base * tone[i] * (1 - 0.35 * g[:, None]) + dark * 0.35 * g[:, None]
        img[m] = c; h[m] = 0.5 + 0.15 * g
    # butt joints along each plank, staggered
    for i in range(n_planks):
        for j in range(2):
            p = (off[i] + j * 0.5) % 1.0
            band = (np.abs(((u - p + 0.5) % 1.0) - 0.5) < 0.0025) & (k == i)
            img[band] *= 0.35; h[band] -= 0.3
    if gaps:
        g = (fv < 0.035) | (fv > 0.965); img[g] *= 0.25; h[g] -= 0.4
    # wear (lighter scuffs) and grime (darker blotches), tileable
    wear = np.clip(tnoise((S, S), S / 40, seed + 2) * 1.6 - 0.4, 0, 1)
    grime = np.clip(tnoise((S, S), S / 18, seed + 3) * 1.5 - 0.2, 0, 1)
    img = img * (1 + 0.25 * wear[..., None]) * (1 - 0.45 * grime[..., None])
    specks = gaussian_filter((r.random((S, S)) > 0.9993).astype(float), 1.2, mode='wrap') * 30
    img *= (1 - np.clip(specks, 0, 0.6))[..., None]
    if gloss_streak:
        img *= (1 + 0.12 * tnoise((S, S), (S / 6, S / 2), seed + 4))[..., None]
    return img, h

floor, fh = planks(1024, 8, np.array([0.30, 0.19, 0.11]), np.array([0.08, 0.05, 0.03]), True, 11)
# sticky dark spills on the floor
spill = np.clip(tnoise((1024, 1024), 45, 12) * 2.2 - 1.1, 0, 1)
floor *= (1 - 0.5 * spill[..., None])
save(floor, 'floor_wood.png'); normal_from(gaussian_filter(fh, 1.2, mode='wrap'), 2.5, 'floor_wood_n.png')

panel, ph = planks(512, 6, np.array([0.26, 0.15, 0.08]), np.array([0.07, 0.04, 0.02]), False, 21)
save(panel, 'panel_wood.png'); normal_from(gaussian_filter(ph, 1.0, mode='wrap'), 2.0, 'panel_wood_n.png')

bar, bh = planks(1024, 3, np.array([0.24, 0.12, 0.06]), np.array([0.06, 0.03, 0.015]), True, 31, gaps=True, gloss_streak=True)
# glass rings on the bar top
im = Image.fromarray((np.clip(bar, 0, 1) * 255).astype(np.uint8)); d = ImageDraw.Draw(im)
for _ in range(22):
    cx, cy, rr = rng.integers(40, 984), rng.integers(40, 984), rng.integers(18, 34)
    d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=(38, 20, 10), width=3)
save_im(im, 'bar_wood.png'); normal_from(gaussian_filter(bh, 1.0, mode='wrap'), 1.5, 'bar_wood_n.png')

# ---------------------------------------------------------------- felt, vinyl, ceiling tin
S = 512
f = np.ones((S, S, 3)) * np.array([0.06, 0.28, 0.14])
f *= (1 + 0.18 * tnoise((S, S), 2, 41) + 0.12 * tnoise((S, S), 40, 42))[..., None]
stains = np.clip(tnoise((S, S), 25, 43) * 2 - 1.2, 0, 1); f *= (1 - 0.4 * stains[..., None])
save(f, 'felt.png')

vy = np.ones((S, S, 3)) * np.array([0.42, 0.06, 0.06])
cr = np.abs(tnoise((S, S), 3, 51)); cracks = (cr < 0.035).astype(float)
cracks = gaussian_filter(cracks, 0.6, mode='wrap')
vy *= (1 + 0.15 * tnoise((S, S), 30, 52))[..., None]
vy = vy * (1 - 0.45 * cracks[..., None]) + np.array([0.75, 0.68, 0.55]) * 0.12 * cracks[..., None]
# tufting buttons in a diamond grid
vh = np.zeros((S, S))
yy, xx = np.mgrid[0:S, 0:S]
for gy in range(0, S + 1, 128):
    for gx in range(0, S + 1, 128):
        for ox, oy in ((0, 0), (64, 64)):
            dd = np.hypot(((xx - gx - ox + S / 2) % S) - S / 2, ((yy - gy - oy + S / 2) % S) - S / 2)
            vh += np.exp(-(dd / 30) ** 2)
vy *= (1 - 0.35 * np.clip(vh, 0, 1))[..., None]
save(vy, 'vinyl_red.png'); normal_from(gaussian_filter(-vh, 2, mode='wrap'), 3.0, 'vinyl_red_n.png')

t = np.zeros((S, S)); c = S / 2
for rad in (230, 180, 120, 60):
    dd = np.maximum(np.abs(xx - c), np.abs(yy - c)); t += np.exp(-((dd - rad) / 6) ** 2)
dd = np.hypot(xx - c, yy - c); t += np.exp(-((dd - 90) / 8) ** 2) + np.exp(-((dd - 40) / 10) ** 2)
t += np.exp(-((np.minimum(xx, S - 1 - xx)) / 5) ** 2) + np.exp(-((np.minimum(yy, S - 1 - yy)) / 5) ** 2)
tin = np.ones((S, S, 3)) * np.array([0.10, 0.095, 0.085]) * (1 + 0.45 * np.clip(t, 0, 1))[..., None]
tin *= (1 - 0.4 * np.clip(tnoise((S, S), 30, 61) * 1.5 - 0.3, 0, 1))[..., None]
save(tin, 'ceiling_tin.png'); normal_from(gaussian_filter(t, 1.5), 3.0, 'ceiling_tin_n.png')

# exposed brick, darker and sootier than outside (from the bar's own brick tile)
brick = np.asarray(Image.open(os.path.join(HERE, 'bar_src', 'brick_albedo.png')).convert('RGB'), np.float32) / 255
brick = brick * 0.62 * (1 - 0.25 * np.clip(tnoise(brick.shape[:2], 60, 71) * 1.5, 0, 1))[..., None]
save(brick, 'brick_dark.png')
Image.open(os.path.join(HERE, 'bar_src', 'brick_normal.png')).convert('RGB').save(os.path.join(OUT, 'brick_dark_n.jpg'), quality=92)

# ---------------------------------------------------------------- neon signs (RGBA: tubes + glow on a transparent board)
def neon(name, W, H, lines, color, board=(14, 12, 12, 235)):
    """lines: [(text, font, size, y)]; returns RGBA with tube core + coloured glow"""
    base = Image.new('L', (W, H), 0); d = ImageDraw.Draw(base)
    for text, font, size, y in lines:
        ft = ImageFont.truetype(font, size)
        w = d.textlength(text, font=ft)
        d.text(((W - w) / 2, y), text, font=ft, fill=255, stroke_width=0)
    # tube = outline of the letters
    edge = base.filter(ImageFilter.FIND_EDGES).filter(ImageFilter.MaxFilter(5))
    tube = np.asarray(edge, np.float32) / 255
    glow = gaussian_filter(tube, 9) * 2.2 + gaussian_filter(tube, 24) * 1.5
    col = np.array(color, np.float32)
    rgb = np.clip(col * np.clip(glow, 0, 1)[..., None] + tube[..., None] * (0.55 + 0.45 * col), 0, 1)
    a = np.clip(glow * 0.9 + tube, 0, 1)
    out = np.dstack([rgb, a])
    if board:
        bd = np.zeros((H, W, 4)); bd[..., :3] = np.array(board[:3]) / 255; bd[..., 3] = board[3] / 255
        m = np.zeros((H, W)); m[8:H - 8, 8:W - 8] = 1; bd[..., 3] *= m
        a2 = out[..., 3:4]; out = np.dstack([out[..., :3] * a2 + bd[..., :3] * (1 - a2), np.maximum(a2[..., 0], bd[..., 3])])
    save(out, name, 'RGBA')
    # emission map: just the lit parts
    save(np.clip(col * np.clip(glow, 0, 1)[..., None] + tube[..., None], 0, 1), name.replace('.png', '_e.png'))
neon('neon_lumberjack.png', 1024, 384, [('Lumberjack', F_RYE, 150, 40), ('LAGER  ON  TAP', F_POP, 70, 230)], (1.0, 0.55, 0.12))
neon('neon_coldbeer.png', 768, 384, [('COLD', F_POP, 150, 20), ('BEER', F_POP, 150, 180)], (0.25, 0.65, 1.0))
neon('neon_open.png', 640, 256, [('OPEN', F_SLAB, 170, 20)], (1.0, 0.12, 0.25))
neon('neon_cocktails.png', 896, 320, [('Cocktails', F_SCRIPT, 170, 40)], (0.95, 0.25, 0.85))

# ---------------------------------------------------------------- posters & small signs
def fit(d, text, font, size, maxw):
    ft = ImageFont.truetype(font, size)
    while d.textlength(text, font=ft) > maxw and size > 8:
        size -= 2; ft = ImageFont.truetype(font, size)
    return ft

def poster(name, W, H, bg, items, aged=True, border=None):
    im = Image.new('RGB', (W, H), bg); d = ImageDraw.Draw(im)
    if border: d.rectangle([10, 10, W - 11, H - 11], outline=border, width=8)
    for text, font, size, y, fill in items:
        ft = fit(d, text, font, size, W - 60); w = d.textlength(text, font=ft); d.text(((W - w) / 2, y), text, font=ft, fill=fill)
    a = np.asarray(im, np.float32) / 255
    if aged:
        stain = np.clip(gaussian_filter(np.random.default_rng(len(name)).standard_normal((H, W)), 25) * 6, -1, 1)
        a = a * (0.82 + 0.1 * stain[..., None]) * np.array([1.0, 0.95, 0.85])
        edge = np.minimum(np.minimum(np.mgrid[0:H, 0:W][0], H - 1 - np.mgrid[0:H, 0:W][0]), np.minimum(np.mgrid[0:H, 0:W][1], W - 1 - np.mgrid[0:H, 0:W][1]))
        a *= np.clip(edge / 30, 0.6, 1)[..., None]
    save(a, name)
poster('poster_band.png', 512, 768, (226, 200, 150), [('LIVE', F_SLAB, 120, 40, (150, 20, 20)), ('THE RUSTY', F_RYE, 64, 230, (30, 20, 15)), ('NAILS', F_RYE, 110, 300, (30, 20, 15)),
       ('FRIDAY 9PM', F_POP, 52, 520, (150, 20, 20)), ('NO COVER', F_POP, 40, 610, (30, 20, 15))], border=(30, 20, 15))
poster('poster_league.png', 512, 768, (235, 228, 210), [('POOL', F_SLAB, 110, 40, (20, 70, 40)), ('LEAGUE', F_SLAB, 90, 170, (20, 70, 40)), ('TUESDAYS', F_POP, 54, 330, (30, 30, 30)),
       ('$5 ENTRY', F_POP, 48, 420, (30, 30, 30)), ('WINNER TAKES', F_POP, 40, 520, (30, 30, 30)), ('THE POT', F_POP, 58, 580, (160, 30, 20))], border=(20, 70, 40))
poster('sign_cash.png', 512, 256, (240, 236, 220), [('CASH ONLY', F_SLAB, 80, 30, (170, 20, 20)), ('ATM IS BROKEN', F_POP, 40, 150, (30, 30, 30))], border=(170, 20, 20))
poster('sign_staff.png', 384, 192, (200, 190, 60), [('STAFF', F_SLAB, 72, 20, (20, 20, 20)), ('ONLY', F_SLAB, 52, 105, (20, 20, 20))], border=(20, 20, 20))
poster('sign_restroom.png', 384, 192, (230, 230, 225), [('RESTROOM', F_POP, 52, 40, (25, 25, 25)), ('out of order', F_SCRIPT, 44, 105, (150, 20, 20))], border=(25, 25, 25))
poster('sign_minors.png', 512, 256, (250, 250, 245), [('NO MINORS', F_SLAB, 70, 30, (20, 20, 20)), ('WE CARD', F_POP, 56, 140, (170, 20, 20))], border=(20, 20, 20))

# ---------------------------------------------------------------- liquor labels: 8 invented brands, 4 x 2 atlas (each 256 x 256)
labels = [('PINE HOLLOW', 'RYE', (205, 180, 120), (60, 30, 15)), ('BLACK BEAR', 'WHISKEY', (20, 20, 22), (215, 175, 80)),
          ('GOLD RUSH', 'TEQUILA', (235, 215, 140), (120, 60, 20)), ('CAPT. BARNACLE', 'RUM', (40, 60, 110), (230, 200, 120)),
          ('POLAR', 'VODKA', (230, 240, 250), (30, 60, 120)), ('GATOR', 'GIN', (60, 120, 70), (240, 240, 220)),
          ('MOONSHINE', 'XXX', (240, 236, 220), (30, 30, 30)), ('LUMBERJACK', 'LAGER', (170, 40, 30), (245, 230, 200))]
atlas = Image.new('RGB', (1024, 512)); d = ImageDraw.Draw(atlas)
for i, (a, b, bg, fg) in enumerate(labels):
    x0, y0 = (i % 4) * 256, (i // 4) * 256
    d.rectangle([x0, y0, x0 + 255, y0 + 255], fill=bg)
    d.rectangle([x0 + 10, y0 + 10, x0 + 245, y0 + 245], outline=fg, width=4)
    for text, font, size, yy in ((a, F_SLAB, 30 if len(a) > 10 else 40, 70), (b, F_RYE, 54, 125)):
        ft = fit(d, text, font, size, 220); w = d.textlength(text, font=ft); d.text((x0 + (256 - w) / 2, y0 + yy), text, font=ft, fill=fg)
save_im(atlas, 'labels.png')

# ---------------------------------------------------------------- dartboard, chalkboard, jukebox, TV
S = 512; c = S / 2; im = Image.new('RGBA', (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
d.ellipse([4, 4, S - 4, S - 4], fill=(18, 18, 18, 255))
R = 210
for i in range(20):
    a0 = math.degrees(2 * math.pi * i / 20 - math.pi / 20) - 90; a1 = a0 + 18
    dark = i % 2 == 0
    for r, col in ((R, (190, 30, 30) if dark else (30, 120, 50)), (R * 0.93, (20, 20, 20) if dark else (230, 215, 170)),
                   (R * 0.6, (190, 30, 30) if dark else (30, 120, 50)), (R * 0.54, (20, 20, 20) if dark else (230, 215, 170))):
        d.pieslice([c - r, c - r, c + r, c + r], a0, a1, fill=col)
d.ellipse([c - 22, c - 22, c + 22, c + 22], fill=(30, 120, 50)); d.ellipse([c - 10, c - 10, c + 10, c + 10], fill=(190, 30, 30))
ft = ImageFont.truetype(F_POP, 26)
for i, n in enumerate([20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]):
    a = 2 * math.pi * i / 20 - math.pi / 2; x, y = c + 232 * math.cos(a), c + 232 * math.sin(a)
    w = d.textlength(str(n), font=ft); d.text((x - w / 2, y - 16), str(n), font=ft, fill=(235, 235, 235))
im.save(os.path.join(OUT, 'dartboard.png'))

im = Image.new('RGB', (512, 384), (30, 36, 32)); d = ImageDraw.Draw(im)
chalk = (215, 215, 205)
ft = ImageFont.truetype(F_SCRIPT, 46); d.text((30, 20), "Today's Specials", font=ft, fill=chalk)
ft = ImageFont.truetype(F_POP, 34)
for i, line in enumerate(['Draft  $2', 'Lumberjack  $3', 'Wells  $4', 'Pickled eggs  $1']):
    d.text((40, 110 + i * 60), line, font=ft, fill=chalk)
a = np.asarray(im, np.float32) / 255; a = a * (1 - 0.1 * np.clip(gaussian_filter(rng.standard_normal((384, 512)), 20) * 8, -1, 1))[..., None]
save(a, 'chalkboard.png')

# jukebox front: arched window, coloured glass bubbles, record titles
im = Image.new('RGB', (512, 1024), (25, 18, 14)); d = ImageDraw.Draw(im)
for k, col in enumerate([(255, 120, 30), (255, 40, 80), (90, 200, 255)]):
    m = 30 + k * 26
    d.rounded_rectangle([m, m, 512 - m, 1024 - 100 - k * 10], radius=220 - k * 26, outline=col, width=16)
d.rectangle([140, 300, 372, 520], fill=(235, 225, 190))
ft = ImageFont.truetype(F_POP, 20)
for i in range(8):
    d.text((152, 310 + i * 26), ['A1  Whiskey River', 'A2  Rusty Nails', 'B1  Last Call', 'B2  Pine Hollow Blues', 'C1  Lumberjack Song', 'C2  Two More Beers', 'D1  Cab Ride Home', 'D2  Closing Time'][i], font=ft, fill=(40, 30, 20))
d.rectangle([120, 600, 392, 860], fill=(40, 30, 25))
for i in range(9):
    d.rectangle([140 + i * 28, 620, 156 + i * 28, 840], fill=(200, 180, 120))
save_im(im, 'jukebox.png')
e = np.asarray(im, np.float32) / 255; mask = (e.max(-1) > 0.45).astype(float); save(e * mask[..., None], 'jukebox_e.png')

# TV: a night ballgame
im = Image.new('RGB', (640, 360), (20, 60, 25)); d = ImageDraw.Draw(im)
for i in range(0, 640, 64): d.rectangle([i, 120, i + 31, 360], fill=(26, 75, 30))
d.polygon([(320, 180), (420, 260), (320, 340), (220, 260)], outline=(230, 230, 230), width=4)
d.rectangle([0, 0, 640, 60], fill=(15, 15, 30)); ft = ImageFont.truetype(F_POP, 30)
d.text((20, 12), 'PINE HOLLOW 3   -   RIVERDALE 2    BOT 9', font=ft, fill=(255, 220, 80))
for x in (300, 360, 250): d.ellipse([x, 230, x + 14, 244], fill=(240, 240, 240))
save_im(im, 'tv.png')
print('textures in', OUT, ':', len(os.listdir(OUT)))

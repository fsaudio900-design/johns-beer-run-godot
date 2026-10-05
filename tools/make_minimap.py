#!/usr/bin/env python3
"""Style the top-down town render (game scenario "mapbake") into the minimap image, and draw
the minimap icons (mission, bar, fuel stop, John's arrow).

The render covers x -155..49.8 m (left to right) and z -62..12 m (top to bottom), north (-z) up.
usage: make_minimap.py <map_raw.png> <out dir>"""
import sys, os, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import gaussian_filter, sobel

src, out = sys.argv[1], sys.argv[2]
a = np.asarray(Image.open(src).convert('RGB'), np.float32) / 255
r, g, b = a[..., 0], a[..., 1], a[..., 2]
lum = 0.3 * r + 0.59 * g + 0.11 * b
grass = (g > r * 1.15) & (g > b * 1.15)
# palette: night-blue grass, asphalt, pavement, buildings
ramp = np.array([[0.10, 0.12, 0.15], [0.20, 0.22, 0.26], [0.34, 0.37, 0.42], [0.55, 0.58, 0.64], [0.72, 0.75, 0.80]])
t = np.clip((lum - 0.12) / 0.8, 0, 1) * (len(ramp) - 1)
i0 = np.floor(t).astype(int); i1 = np.minimum(i0 + 1, len(ramp) - 1); f = (t - i0)[..., None]
col = ramp[i0] * (1 - f) + ramp[i1] * f
col[grass] = np.array([0.075, 0.115, 0.11]) * (0.85 + 0.3 * lum[grass, None] / max(lum[grass].mean(), 1e-3))
# soft outlines round everything that isn't grass
edge = np.hypot(sobel(gaussian_filter(lum, 1.0), 0), sobel(gaussian_filter(lum, 1.0), 1))
col = col * (1 - np.clip(edge * 1.6, 0, 0.45)[..., None])
Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8)).save(os.path.join(out, 'minimap.png'))
print('map', a.shape)

S = 128
def icon(name, draw_fn):
    im = Image.new('RGBA', (S * 2, S * 2), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    draw_fn(d, S * 2)
    im = im.resize((S, S), Image.LANCZOS); im.save(os.path.join(out, name))

def disc(d, n, fill, ring=(255, 255, 255, 255)):
    d.ellipse([10, 10, n - 10, n - 10], fill=fill, outline=ring, width=10)

def mission(d, n):        # gold disc with an exclamation mark
    disc(d, n, (255, 196, 40, 255))
    d.rounded_rectangle([n / 2 - 16, 52, n / 2 + 16, 150], radius=14, fill=(40, 25, 5, 255))
    d.ellipse([n / 2 - 18, 168, n / 2 + 18, 204], fill=(40, 25, 5, 255))

def bar(d, n):            # magenta disc with a cocktail glass
    disc(d, n, (214, 60, 150, 255))
    w = (255, 255, 255, 255)
    d.polygon([(70, 70), (186, 70), (128, 140)], fill=w)
    d.rectangle([122, 138, 134, 186], fill=w)
    d.rounded_rectangle([90, 182, 166, 196], radius=6, fill=w)
    d.ellipse([150, 52, 176, 78], fill=(255, 225, 90, 255))

def fuel(d, n):           # green disc with a petrol pump
    disc(d, n, (40, 170, 90, 255))
    w = (255, 255, 255, 255)
    d.rounded_rectangle([76, 60, 150, 196], radius=10, fill=w)
    d.rectangle([90, 78, 136, 112], fill=(40, 170, 90, 255))
    d.rectangle([66, 190, 160, 204], fill=w)
    d.line([(150, 96), (176, 110), (176, 168), (160, 176)], fill=w, width=12)
    d.ellipse([168, 98, 184, 114], fill=w)

def player(d, n):         # John: an arrow
    d.polygon([(n / 2, 20), (n - 40, n - 30), (n / 2, n - 75), (40, n - 30)], fill=(255, 140, 60, 255), outline=(255, 255, 255, 255), width=10)

icon('map_mission.png', mission); icon('map_bar.png', bar); icon('map_fuel.png', fuel); icon('map_player.png', player)
# a soft "!" with glow for the 3D hologram
im = Image.new('RGBA', (256, 512), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
d.rounded_rectangle([98, 40, 158, 360], radius=30, fill=(255, 255, 255, 255))
d.ellipse([96, 400, 160, 464], fill=(255, 255, 255, 255))
glow = im.filter(ImageFilter.GaussianBlur(18))
arr = np.maximum(np.asarray(im, np.float32), np.asarray(glow, np.float32) * 1.3)
arr = np.clip(arr, 0, 255); pm = arr[..., 3:4] / 255.0
arr = np.concatenate([arr[..., :3] * pm, np.full_like(pm, 255)], -1)
Image.fromarray(arr.astype(np.uint8), 'RGBA').save(os.path.join(out, 'holo_mark.png'))
print('icons done')

# hologram textures (white, tinted by the material): beam gradient with scan lines, ground ring
H, W = 512, 64
y = np.linspace(0, 1, H)[:, None]                    # 0 top .. 1 bottom
scan = 0.6 + 0.4 * (np.sin(y * 2 * np.pi * 26) > 0)
x = np.linspace(-1, 1, W)[None, :]
edge = 0.35 + 0.65 * np.abs(x) ** 2.5
a = (y ** 1.7) * scan * edge
img = np.zeros((H, W, 4), np.float32); img[..., :3] = np.clip(a, 0, 1)[..., None]; img[..., 3] = 1.0
Image.fromarray((img * 255).astype(np.uint8), 'RGBA').save(os.path.join(out, 'holo_beam.png'))
N = 256
yy, xx = np.mgrid[0:N, 0:N] / (N - 1) * 2 - 1
rr = np.hypot(xx, yy)
a = np.exp(-((rr - 0.82) / 0.05) ** 2) + 0.55 * np.exp(-((rr - 0.55) / 0.035) ** 2) + 0.18 * np.clip(1 - rr, 0, 1)
a[rr > 1] = 0
img = np.zeros((N, N, 4), np.float32); img[..., :3] = np.clip(a, 0, 1)[..., None]; img[..., 3] = 1.0
Image.fromarray((img * 255).astype(np.uint8), 'RGBA').save(os.path.join(out, 'holo_ring.png'))
print('holo textures done')

"""starfield — stars drifting past in three depths, a few twinkling, and the
odd shooting star.

A layer's stars repeat every 1/3 (far), 1/2 (mid) or 1 (near) tile height and
the layer drifts down by exactly that much over the loop, so slower layers
still loop seamlessly. Drawn at twice the size and scaled down, so slow stars
glide between pixels instead of stepping.
"""
import math, random
from PIL import Image, ImageDraw
from .common import Spec, mix, scale, wave

W, H, SS = 990, 660, 2         # tile, supersampling
FRAMES = 300                   # 12 s at 25 fps
LAYERS = [                     # repeats per tile, stars per repeat, radius, brightness
    (3, 55, (0.6, 0.9), 0.45),
    (2, 40, (0.9, 1.4), 0.70),
    (1, 34, (1.3, 2.2), 1.00),
]

def spec(theme):
    rng = random.Random(7)
    tints = [theme.white, mix(theme.white, theme.accent, 0.6), mix(theme.white, theme.accent2, 0.6)]
    stars = []                 # (layer repeats, x, y within its band, r, colour, twinkle cycles, phase)
    for reps, n, (r0, r1), bright in LAYERS:
        band = H / reps
        for _ in range(n):
            tw = rng.choice((0, 0, 0, 0, 2, 3, 4))
            stars.append((reps, rng.uniform(0, W), rng.uniform(0, band), rng.uniform(r0, r1),
                          scale(rng.choice(tints), bright * rng.uniform(0.7, 1.0)), tw, rng.random()))
    meteors = [(0.22, rng.uniform(0.3, 0.9) * W, rng.uniform(0.05, 0.3) * H),
               (0.71, rng.uniform(0.2, 0.8) * W, rng.uniform(0.05, 0.35) * H)]

    def draw(t, i):
        img = Image.new("RGB", (W * SS, H * SS), theme.black)
        d = ImageDraw.Draw(img)
        for reps, x, y0, r, c, tw, ph in stars:
            band = H / reps
            y = (y0 + band * t) % band                 # drifts one band per loop
            if tw:
                c = scale(c, 0.55 + 0.45 * wave(t, tw, ph))
            for k in range(reps + 1):                  # one copy per band, plus the one wrapping in
                yy = y + (k - 1) * band
                if -r <= yy <= H + r:
                    for dx in (-W, 0, W):              # and across the side edge
                        if -r <= x + dx <= W + r:
                            cx, cy, rr = (x + dx) * SS, yy * SS, r * SS
                            d.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=c)
        for t0, mx, my in meteors:                     # a streak over 14 frames, fading tail
            p = (t - t0) / (14 / FRAMES)
            if 0 <= p <= 1:
                hx, hy = mx + 260 * p, my + 120 * p
                for s in range(12):
                    a = (1 - s / 12) * (1 - p) ** 0.5
                    x0, y0 = hx - 9 * s, hy - 9 * s * 120 / 260
                    d.line(((x0 - 9) * SS, (y0 - 4.15) * SS, x0 * SS, y0 * SS),
                           fill=scale(theme.white, a), width=max(1, int(2 * SS * (1 - s / 12))))
        return img.resize((W, H), Image.LANCZOS)

    return Spec(W, H, FRAMES, 40, draw, colours=64, delta=True)

"""snow — flakes falling in three depths, swaying in a gentle wind.

Like the starfield: a layer's flakes repeat every 1/3, 1/2 or 1 tile height and
fall exactly that far per loop. The wind is a sway with a whole number of
cycles per loop (each flake's own, plus a gust the whole layer shares), so the
loop stays seamless.
"""
import random
from PIL import Image, ImageDraw
from .common import Spec, mix, scale, wave

W, H, SS = 990, 660, 2
FRAMES = 300                   # 12 s at 25 fps
LAYERS = [                     # repeats per tile, flakes per repeat, radius, brightness, sway px
    (3, 70, (0.9, 1.4), 0.45, 5),
    (2, 50, (1.8, 2.8), 0.70, 10),
    (1, 26, (3.4, 5.2), 0.95, 18),
]

def spec(theme):
    rng = random.Random(11)
    flakes = []
    for reps, n, (r0, r1), bright, sway in LAYERS:
        band = H / reps
        tint = mix(theme.white, theme.accent, 0.8 if reps > 1 else 0.92)
        for _ in range(n):
            flakes.append((reps, rng.uniform(0, W), rng.uniform(0, band), rng.uniform(r0, r1),
                           scale(tint, bright * rng.uniform(0.75, 1.0)), sway * rng.uniform(0.5, 1.0),
                           rng.choice((1, 2, 3)), rng.random(), sway))

    def draw(t, i):
        img = Image.new("RGB", (W * SS, H * SS), theme.black)
        d = ImageDraw.Draw(img)
        for reps, x0, y0, r, c, amp, cyc, ph, gust in flakes:
            band = H / reps
            y = (y0 + band * t) % band
            x = x0 + amp * wave(t, cyc, ph) + gust * 0.8 * wave(t, 1, 0.1 * reps)   # own sway + shared gust
            for k in range(reps + 1):
                yy = y + (k - 1) * band
                if -r <= yy <= H + r:
                    for dx in (-W, 0, W):
                        cx = x + dx
                        if -r <= cx <= W + r:
                            X, Y, R = cx * SS, yy * SS, r * SS
                            if r > 1.6:                        # nearer flakes are soft: two faint rims
                                d.ellipse((X - R * 1.9, Y - R * 1.9, X + R * 1.9, Y + R * 1.9), fill=scale(c, 0.18))
                                d.ellipse((X - R * 1.4, Y - R * 1.4, X + R * 1.4, Y + R * 1.4), fill=scale(c, 0.45))
                            d.ellipse((X - R, Y - R, X + R, Y + R), fill=c)
        return img.resize((W, H), Image.LANCZOS)

    return Spec(W, H, FRAMES, 40, draw, colours=64, delta=True)

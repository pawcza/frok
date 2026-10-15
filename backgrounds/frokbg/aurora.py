"""aurora — slow curtains of light in the theme's two accents, over a few
faint stars.

Every curtain's shape is a sum of sines with a whole number of cycles across
the tile (so it tiles side by side) and a whole number of cycles over the loop
(so it loops). Rendered small and soft, then left to the terminal to stretch:
an aurora has no hard edges to lose.
"""
import random
from PIL import Image, ImageDraw, ImageChops, ImageFilter
from .common import Spec, mix, scale, wave

W, H = 480, 320
FRAMES = 150                   # 12 s at 12.5 fps: slow light needs few frames
STEP = 2                       # px between rays

def spec(theme):
    rng = random.Random(5)
    curtains = []
    for k in range(3):
        curtains.append(dict(
            base=H * rng.uniform(0.42, 0.62), height=H * rng.uniform(0.28, 0.42),
            bends=[(rng.choice((1, 2)), rng.choice((1, -1)), rng.random(), H * rng.uniform(0.04, 0.09)),
                   (rng.choice((2, 3)), rng.choice((1, -1)), rng.random(), H * rng.uniform(0.02, 0.05))],
            rays=(rng.choice((17, 19, 23)), rng.choice((1, -1)), rng.random(), rng.choice((5, 7))),
            hue=(rng.choice((1, 2)), rng.random()),
            bright=(1.0, 0.75, 0.55)[k]))
    stars = [(rng.randrange(W), rng.randrange(int(H * 0.7)), rng.uniform(0.25, 0.6)) for _ in range(70)]

    def draw(t, i):
        img = Image.new("RGB", (W, H), theme.black)
        d = ImageDraw.Draw(img)
        for x, y, b in stars:
            d.point((x, y), fill=scale(theme.white, b))
        for c in curtains:
            layer = Image.new("RGB", (W, H), (0, 0, 0))
            ld = ImageDraw.Draw(layer)
            for x in range(0, W, STEP):
                u = x / W
                y = c["base"] + sum(a * wave(t, sgn, ph + n * u) for n, sgn, ph, a in c["bends"])
                rk, rs, rp, rk2 = c["rays"]                 # fine rays drifting along the curtain
                glow = c["bright"] * (0.5 + 0.3 * wave(t, rs, rp + rk * u) + 0.2 * wave(t, -rs, rp * 2 + rk2 * u)) \
                       * (0.6 + 0.4 * wave(t, 1, 0.3 + 2 * u))
                hk, hp = c["hue"]
                colour = mix(theme.accent, theme.accent2, 0.5 + 0.5 * wave(t, 1, hp + hk * u))
                h = c["height"] * (0.75 + 0.25 * wave(t, 1, rp + 3 * u))
                seg = 8                                   # bright at the lower edge, fading up
                for j in range(seg):
                    f = (1 - j / seg) ** 1.6
                    y0, y1 = y - h * j / seg, y - h * (j + 1) / seg
                    ld.line((x, y0, x, y1), fill=scale(colour, glow * f), width=STEP)
                for j in range(3):                        # and a short glow below the edge
                    f = 0.55 * (1 - j / 3) ** 2
                    ld.line((x, y + h * 0.03 * j, x, y + h * 0.03 * (j + 1)), fill=scale(colour, glow * f), width=STEP)
            img = ImageChops.add(img, layer.filter(ImageFilter.GaussianBlur(2.5)))
        return img

    return Spec(W, H, FRAMES, 80, draw, colours=192)

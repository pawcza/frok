"""rain — digital rain in three depths.

Far columns are small, dim and slow; near ones large, bright and fast, with
glowing heads. Each column is a strip exactly one tile tall with 1-2 comets
baked in, scrolled down by a whole number of tile heights over the loop, so
the last frame meets the first and the tile repeats seamlessly both ways.
"""
import random
from PIL import Image, ImageDraw, ImageFilter, ImageChops
from .common import Spec, font, mix, scale

W, H = 990, 660          # 3:2, divisible by every layer's row height below
FRAMES = 220             # 8.8 s at 25 fps
KATAKANA = [chr(c) for c in range(0xFF66, 0xFF9E)]
LATIN = list("0123456789ABCDEFGHJKLMNPQRSTUVWXYZ:.=*+<>")

# name, font size, row height, scrolls per loop, brightness, columns, glow
LAYERS = [
    ("far",  11, 15, (1,),       0.38, 30, False),
    ("mid",  15, 20, (1, 2),     0.68, 24, True),
    ("near", 21, 30, (2, 2, 3),  1.00, 10, True),
]

class Column:
    def __init__(self, rng, x, rows, row_h, speeds, nglyphs):
        self.x, self.row_h = x, row_h
        self.k = rng.choice(speeds)
        self.glyph = [rng.randrange(nglyphs) for _ in range(rows)]
        self.lit = []                                   # (row, level 0..1) along the comets
        comets = [(rng.randrange(rows), rng.randint(rows // 4, rows // 2 + 2)) for _ in range(rng.choice((1, 1, 2)))]
        for r in range(rows):
            level = max((1 - ((head - r) % rows) / trail for head, trail in comets if (head - r) % rows < trail), default=0)
            if level > 0.04:
                self.lit.append((r, level))

def spec(theme):
    rng = random.Random(42)
    layers = []
    for name, size, row_h, speeds, bright, count, glow in LAYERS:
        f, kata = font(size)
        glyphs = (KATAKANA + LATIN) if kata else LATIN
        cw = int(size * 0.95)
        xs = rng.sample(range(0, W - cw, max(1, cw // 2)), count)
        cols = [Column(rng, x, H // row_h, row_h, speeds, len(glyphs)) for x in xs]
        tail = scale(mix(theme.accent, theme.accent2, 0.75 if name == "far" else 1), 0.25)
        trail = mix(theme.accent, theme.accent2, 0.6 if name == "far" else 0.9)
        head = theme.white
        layers.append((f, glyphs, cols, bright, glow, tail, trail, head))

    def shade(layer, level):
        _, _, _, bright, _, tail, trail, head = layer
        c = head if level >= 0.97 else mix(trail, tail, level ** 0.8)
        return scale(c, bright)

    def draw(t, i):
        img = Image.new("RGB", (W, H), theme.black)
        glow = Image.new("RGB", (W, H), (0, 0, 0))
        d, g = ImageDraw.Draw(img), ImageDraw.Draw(glow)
        flick = i // 4                                   # bright glyphs shimmer every 4 frames
        for layer in layers:
            f, glyphs, cols, bright, has_glow, *_ = layer
            for col in cols:
                py = col.k * H * t
                for r, level in col.lit:
                    ch = glyphs[(col.glyph[r] + (flick if level > 0.55 else 0)) % len(glyphs)]
                    y = (r * col.row_h + py) % H
                    colour = shade(layer, level)
                    for yy in (y - H, y):                # the strip wraps around the tile
                        if -col.row_h < yy < H:
                            d.text((col.x, yy), ch, font=f, fill=colour)
                            if has_glow and level >= 0.97:
                                g.text((col.x, yy), ch, font=f, fill=scale(colour, 0.9))
        return ImageChops.add(img, glow.filter(ImageFilter.GaussianBlur(5)))

    return Spec(W, H, FRAMES, 40, draw, colours=64)

#!/usr/bin/env python3
"""Generate a PERFECTLY LOOPING Matrix digital-rain GIF.

Loop trick: each column is a fixed vertical "strip" texture (glyphs + a baked
comet brightness profile). Over the whole animation, column c scrolls down by
exactly k[c] whole strip-heights. Because the scroll offset returns to 0 (mod
strip height) at the final frame, frame FRAMES is identical to frame 0 -> the
GIF loops with no visible seam.
"""
import os, random
from PIL import Image, ImageDraw, ImageFont

random.seed(42)  # deterministic / reproducible

W, H = 990, 660          # exactly 55x30 cells (18x22 px), so the tile wraps seamlessly
FONT_SIZE = 18
FRAMES = 220              # 660px / 220 = exactly 3px per frame: no rounding wobble
DURATION_MS = 40          # 25fps (wezterm animation_fps must match)
HEAD = (192, 202, 245)    # Tokyo Night fg, for the drop heads
BRIGHT = (122, 162, 247)  # Tokyo Night blue #7aa2f7
DIM = (26, 34, 70)
BG = (0, 0, 0)

FONT_CANDIDATES = [
    "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/System/Library/Fonts/Supplemental/Osaka.ttf",
    "/System/Library/Fonts/Menlo.ttc",
]
KATAKANA = [chr(c) for c in range(0xFF66, 0xFF9E)]
LATIN = list("0123456789ABCDEFGHJKLMNPQRSTUVWXYZ:.=*+<>")

def load_font():
    for path in FONT_CANDIDATES:
        if not os.path.exists(path):
            continue
        try:
            f = ImageFont.truetype(path, FONT_SIZE)
        except Exception:
            continue
        probe = Image.new("RGB", (40, 40))
        bb = ImageDraw.Draw(probe).textbbox((0, 0), "ｱ", font=f)
        has_kata = (bb[2] - bb[0]) > 2 and (bb[3] - bb[1]) > 2
        return f, has_kata, path
    return ImageFont.load_default(), False, "default"

FONT, HAS_KATA, FONT_PATH = load_font()
GLYPHS = (KATAKANA + LATIN) if HAS_KATA else LATIN
NG = len(GLYPHS)

CELL_W = FONT_SIZE
CELL_H = FONT_SIZE + 4
COLS = W // CELL_W
ROWS = H // CELL_H

def shade(level):
    if level >= 0.97:
        return HEAD
    return tuple(int(DIM[k] + (BRIGHT[k] - DIM[k]) * level) for k in range(3))

# ── Build one static strip per column ─────────────────────────────────
class Column:
    def __init__(self, cx):
        self.x = cx * CELL_W
        # strip height in rows; taller than screen so the pattern doesn't
        # obviously repeat within one screen.
        self.srows = ROWS        # strip = tile height, so it wraps seamlessly when tiled vertically
        self.sp = self.srows * CELL_H          # strip pixel height
        self.k = random.choice([1, 1, 1, 1, 1, 2])  # whole scrolls / animation (slower, calmer)
        self.base_idx = [random.randrange(NG) for _ in range(self.srows)]
        # 1-2 comets baked into the strip
        ncom = random.choice([1, 1, 2])
        comets = []
        for _ in range(ncom):
            comets.append((random.randrange(self.srows), random.randint(7, 20)))
        # precompute lit rows: (row, level)
        self.lit = []
        for r in range(self.srows):
            best = 0.0
            for head, trail in comets:
                d = (head - r) % self.srows
                if d < trail:
                    best = max(best, 1.0 - d / trail)
            if best > 0.02:
                self.lit.append((r, best))

    def draw(self, draw, f):
        py = (self.k * self.sp) * (f / FRAMES)   # smooth scroll (px), loops at f=FRAMES
        flick = f // 4
        for r, level in self.lit:
            color = shade(level)
            # flicker glyph a bit as it falls (shimmer); seam flick is harmless
            g = GLYPHS[(self.base_idx[r] + flick) % NG] if level > 0.55 else GLYPHS[self.base_idx[r]]
            yb = (r * CELL_H + py) % self.sp
            for yy in (yb - self.sp, yb, yb + self.sp):
                if -CELL_H < yy < H:
                    draw.text((self.x, yy), g, font=FONT, fill=color)

cols = [Column(c) for c in range(COLS)]

frames = []
for fi in range(FRAMES):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    for col in cols:
        col.draw(d, fi)
    frames.append(img)

pal = [f.convert("P", palette=Image.ADAPTIVE, colors=48) for f in frames]
out = os.path.expanduser("~/.config/wezterm/rain-tokyo-tile-25.gif")
pal[0].save(out, save_all=True, append_images=pal[1:],
            duration=DURATION_MS, loop=0, optimize=True, disposal=2)
print("font:", FONT_PATH, "| katakana:", HAS_KATA, "| glyphs:", NG)
print("grid:", COLS, "x", ROWS, "| frames:", len(frames))
print("saved:", out, "| size:", round(os.path.getsize(out)/1024), "KB")

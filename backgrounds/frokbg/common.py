"""Shared pieces: theme colours, the loop driver and the GIF writer."""
import math, os
from dataclasses import dataclass
from typing import Callable
from PIL import Image, ImageFont, ImageDraw, ImageChops

def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

def mix(a, b, w):
    """w of colour a, the rest b (w in 0..1)."""
    return tuple(int(round(a[k] * w + b[k] * (1 - w))) for k in range(3))

def scale(c, s):
    return tuple(max(0, min(255, int(round(v * s)))) for v in c)

class Theme:
    """The theme's colours. Backgrounds are drawn on near-black, because frok
    shows them faintly (about 20%) behind the terminal's own background."""
    def __init__(self, fg, accent, accent2, bg):
        self.fg, self.accent, self.accent2, self.bg = rgb(fg), rgb(accent), rgb(accent2), rgb(bg)
        self.black = scale(self.bg, 0.35)
        self.white = mix(self.fg, (255, 255, 255), 0.55)

@dataclass
class Spec:
    width: int
    height: int
    frames: int                       # one loop; frame `frames` would equal frame 0
    duration_ms: int                  # per frame
    draw: Callable[[float, int], Image.Image]   # (t in [0,1), frame index) -> RGB frame
    colours: int = 128                # size of the shared palette
    delta: bool = False               # store only changed pixels (helps sparse effects, hurts busy ones)

def wave(t, cycles=1, phase=0.0):
    """A sine that completes whole cycles over the loop: seamless by design."""
    return math.sin(2 * math.pi * (t * cycles + phase))

def write_gif(out, spec: Spec):
    """Render every frame, quantise them all to one palette built from a sample
    of frames (no palette flicker), and save a looping GIF. With spec.delta a
    frame stores only the pixels that changed (the rest are transparent and
    show the frame before), which shrinks effects that are mostly still."""
    frames = [spec.draw(i / spec.frames, i) for i in range(spec.frames)]
    sample = frames[:: max(1, len(frames) // 12)]
    mosaic = Image.new("RGB", (spec.width, spec.height * len(sample)))
    for k, f in enumerate(sample):
        mosaic.paste(f, (0, k * spec.height))
    colours = min(spec.colours, 255)                  # index 255 stays free for "unchanged"
    palette = mosaic.quantize(colors=colours, method=Image.Quantize.MEDIANCUT)
    pal_bytes = palette.getpalette()[: colours * 3] + [0, 0, 0] * (256 - colours)
    idx = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in frames]
    as_l = lambda p: Image.frombytes("L", p.size, p.tobytes())
    keep = Image.new("L", (spec.width, spec.height), 255)
    out_frames = []
    for k, p in enumerate(idx):
        cur = as_l(p)
        if k and spec.delta:
            changed = ImageChops.difference(cur, as_l(idx[k - 1])).point(lambda v: 255 if v else 0)
            cur = Image.composite(cur, keep, changed)
        q = Image.frombytes("P", p.size, cur.tobytes()); q.putpalette(pal_bytes)
        out_frames.append(q)
    os.makedirs(os.path.dirname(os.path.abspath(out)) or ".", exist_ok=True)
    tmp = out + ".tmp.gif"
    out_frames[0].save(tmp, save_all=True, append_images=out_frames[1:], duration=spec.duration_ms,
                       loop=0, optimize=False, disposal=1, **({"transparency": 255} if spec.delta else {}))
    os.replace(tmp, out)
    return os.path.getsize(out)

# Fonts with katakana first (macOS, Linux, Windows seen from WSL), then any mono.
FONT_CANDIDATES = [
    "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/System/Library/Fonts/Supplemental/Osaka.ttf",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc",
    "/mnt/c/Windows/Fonts/msgothic.ttc",
    "/mnt/c/Windows/Fonts/YuGothR.ttc",
    "/mnt/c/Windows/Fonts/meiryo.ttc",
    "/System/Library/Fonts/Menlo.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/mnt/c/Windows/Fonts/consola.ttf",
]

def font(size):
    """(font, has_katakana) — the first candidate that loads."""
    for path in FONT_CANDIDATES:
        if not os.path.exists(path):
            continue
        try:
            f = ImageFont.truetype(path, size)
        except Exception:
            continue
        bb = ImageDraw.Draw(Image.new("RGB", (40, 40))).textbbox((0, 0), "ｱ", font=f)
        return f, (bb[2] - bb[0]) > 2 and (bb[3] - bb[1]) > 2
    return ImageFont.load_default(), False

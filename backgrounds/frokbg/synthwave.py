"""synthwave — a neon grid rolling toward you under a striped sun.

The grid's cross lines sit at depths k - t: over one loop every line moves into
the place of the one in front of it, so the last frame meets the first. The
sun's stripes slide down by exactly one stripe per loop for the same reason.
"""
import random
from PIL import Image, ImageDraw, ImageChops, ImageFilter
from .common import Spec, mix, scale, wave

W, H, SS = 960, 640, 2
FRAMES = 60                    # 2.4 s at 25 fps: one grid square per loop
HORIZON = 0.58                 # of the height
SUN_R = 0.27                   # of the height

def spec(theme):
    rng = random.Random(3)
    hz = H * HORIZON
    stars = [(rng.uniform(0, W), rng.uniform(0, hz * 0.85), rng.uniform(0.3, 0.8), rng.choice((0, 0, 1, 2)), rng.random())
             for _ in range(60)]
    top, bottom = mix(theme.accent2, theme.white, 0.8), scale(theme.accent, 0.95)   # sun: light top, accent bottom
    grid = theme.accent2

    def draw(t, i):
        S = lambda v: v * SS
        img = Image.new("RGB", (S(W), S(H)), theme.black)
        d = ImageDraw.Draw(img)
        for x, y, b, tw, ph in stars:
            if tw: b *= 0.6 + 0.4 * wave(t, tw, ph)
            d.ellipse((S(x) - 1.5, S(y) - 1.5, S(x) + 1.5, S(y) + 1.5), fill=scale(theme.white, b))
        # the sun: horizontal bands, cut by stripes that thicken toward the horizon and slide down
        cx, cy, r = W / 2, hz - H * SUN_R * 0.35, H * SUN_R
        sun = Image.new("RGB", (S(W), S(H)), (0, 0, 0))
        sd = ImageDraw.Draw(sun)
        for y in range(int(cy - r), int(min(cy + r, hz))):
            dy = (y - cy) / r
            half = r * max(0.0, 1 - dy * dy) ** 0.5
            if y > cy - r * 0.1:                                     # stripes in the lower part
                period = 22
                p = ((y - (cy - r * 0.1)) - period * t) % period
                gap = 2 + 9 * (y - (cy - r * 0.1)) / (r * 1.1)
                if p < gap:
                    continue
            c = mix(top, bottom, max(0.0, 1 - (dy + 1) / 1.6))
            sd.line((S(cx - half), S(y), S(cx + half), S(y)), fill=c, width=SS)
        glow = sun.filter(ImageFilter.GaussianBlur(S(18)))
        img = ImageChops.add(img, scale_img(glow, 0.35))
        img.paste(sun, mask=sun.convert("L").point(lambda v: 255 if v else 0))   # over its glow, not added to it
        # the floor: dark, then the grid with a soft glow
        floor = Image.new("RGB", (S(W), S(H)), (0, 0, 0))
        fd = ImageDraw.Draw(floor)
        fd.rectangle((0, S(hz), S(W), S(H)), fill=scale(theme.black, 0.6))
        lines = Image.new("RGB", (S(W), S(H)), (0, 0, 0))
        ld = ImageDraw.Draw(lines)
        depth = H * 0.9
        for k in range(1, 40):                                       # cross lines, coming closer
            z = k - t
            y = hz + depth / (z * 2.2)
            if y > H or y - hz < 3: continue                         # too far: they'd pile up into a band
            fade = min(1.0, (y - hz) / (H * 0.14))
            ld.line((0, S(y), S(W), S(y)), fill=scale(grid, 0.12 + 0.88 * fade ** 1.3), width=max(1, int(SS * (0.6 + 1.6 * fade))))
        for k in range(-24, 25):                                     # lines running to the vanishing point
            xb = W / 2 + k * W / 10
            ld.line((S(W / 2 + k * 1.2), S(hz), S(xb), S(H)), fill=scale(grid, 0.8), width=SS * 2)
        lines = ImageChops.multiply(lines, mask_below(S(W), S(H), S(hz)))
        img = Image.composite(floor, img, mask_below(S(W), S(H), S(hz)).convert("L"))
        img = ImageChops.add(img, scale_img(lines.filter(ImageFilter.GaussianBlur(S(4))), 0.8))
        img = ImageChops.add(img, lines)
        return img.resize((W, H), Image.LANCZOS)

    return Spec(W, H, FRAMES, 40, draw, colours=160)

def scale_img(im, s):
    return im.point(lambda v: int(v * s))

_masks = {}
def mask_below(w, h, y):
    """White below the horizon, black above (cached)."""
    key = (w, h, int(y))
    if key not in _masks:
        m = Image.new("RGB", (w, h), (0, 0, 0))
        ImageDraw.Draw(m).rectangle((0, int(y), w, h), fill=(255, 255, 255))
        _masks[key] = m
    return _masks[key]

#!/usr/bin/env python3
"""term2gif: record real terminal programs and turn them into crisp GIFs.

  term2gif.py record <out.clip> <cols> <rows> <seconds> <fps> <theme.json> <command>
      Runs <command> in a pty, feeds it stdin (keys), and keeps the screen as a
      tiny terminal emulator sees it, <fps> times a second.

  term2gif.py gif <out.gif> <fps> [--grid <columns>] [--skip <seconds>] [--colours <n>]
                  [--background <effect>:<opacity>]... <clip>:<title>...
      Draws the clips in a window frame coloured by their theme. One after the
      other by default; --grid plays them side by side. --background puts an
      animated frok background behind each clip.

Needs Python with Pillow. Uses CaskaydiaCove Nerd Font when it can find it
(FROK_SHOT_FONTS, ~/.local/share/fonts, the Windows fonts folder).
"""
import fcntl, json, os, pickle, pty, re, select, struct, sys, termios, time
from PIL import Image, ImageChops, ImageDraw, ImageFont

def load_theme(path):
    t = json.load(open(path))
    pal = t["ansi"] + t["brights"]
    for i in range(16, 256):                      # xterm 256-colour cube and greys
        if i < 232:
            n = i - 16
            pal.append("#%02x%02x%02x" % tuple((0, 95, 135, 175, 215, 255)[c] for c in (n // 36, n // 6 % 6, n % 6)))
        else:
            g = 8 + (i - 232) * 10
            pal.append("#%02x%02x%02x" % (g, g, g))
    return t, pal

class Screen:
    def __init__(self, cols, rows):
        self.cols, self.rows = cols, rows
        self.main = self.blank(); self.alt = None
        self.y = self.x = 0; self.saved = (0, 0)
        self.attr = self.reset(); self.wrap = True

    def blank(self): return [[(" ", None, None, 0) for _ in range(self.cols)] for _ in range(self.rows)]
    def reset(self): return {"fg": None, "bg": None, "bold": 0, "dim": 0, "rev": 0}
    @property
    def buf(self): return self.alt if self.alt is not None else self.main

    def put(self, ch):
        if self.x >= self.cols:
            if not self.wrap: return
            self.x = 0; self.lf()
        a = self.attr
        fg, bg = (a["bg"], a["fg"]) if a["rev"] else (a["fg"], a["bg"])
        if a["rev"] and fg is None: fg = "BG"
        if a["rev"] and bg is None: bg = "FG"
        self.buf[self.y][self.x] = (ch, fg, bg, a["bold"] | (a["dim"] << 1))
        self.x += 1

    def lf(self):
        if self.y < self.rows - 1: self.y += 1
        else: self.buf.pop(0); self.buf.append([(" ", None, None, 0) for _ in range(self.cols)])

    def sgr(self, ps, pal):
        ps = ps or [0]; i = 0
        while i < len(ps):
            p = ps[i]
            if p == 0: self.attr = self.reset()
            elif p == 1: self.attr["bold"] = 1
            elif p == 2: self.attr["dim"] = 1
            elif p == 22: self.attr["bold"] = self.attr["dim"] = 0
            elif p == 7: self.attr["rev"] = 1
            elif p == 27: self.attr["rev"] = 0
            elif 30 <= p <= 37: self.attr["fg"] = pal[p - 30]
            elif 90 <= p <= 97: self.attr["fg"] = pal[p - 90 + 8]
            elif p == 39: self.attr["fg"] = None
            elif 40 <= p <= 47: self.attr["bg"] = pal[p - 40]
            elif 100 <= p <= 107: self.attr["bg"] = pal[p - 100 + 8]
            elif p == 49: self.attr["bg"] = None
            elif p in (38, 48) and i + 1 < len(ps):
                key = "fg" if p == 38 else "bg"
                if ps[i + 1] == 5 and i + 2 < len(ps): self.attr[key] = pal[ps[i + 2]]; i += 2
                elif ps[i + 1] == 2 and i + 4 < len(ps): self.attr[key] = "#%02x%02x%02x" % tuple(ps[i + 2:i + 5]); i += 4
            i += 1

    TOKEN = re.compile(r"\x1b\[([?<>=]?)([0-9;]*)([ -/]*)([@-~])|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b([78=>]|[()].)|([^\x1b])", re.S)

    def feed(self, data, pal):
        for m in self.TOKEN.finditer(data):
            priv, params, _, final, esc, ch = m.group(1), m.group(2), m.group(3), m.group(4), m.group(5), m.group(6)
            if ch is not None:
                if ch == "\r": self.x = 0
                elif ch == "\n": self.lf()
                elif ch == "\b": self.x = max(0, self.x - 1)
                elif ch == "\t": self.x = min(self.cols - 1, (self.x // 8 + 1) * 8)
                elif ch >= " ": self.put(ch)
            elif esc is not None:
                if esc.startswith("7"): self.saved = (self.y, self.x)
                elif esc.startswith("8"): self.y, self.x = self.saved
            elif final is not None:
                ps = [int(p) if p else 0 for p in params.split(";")] if params else []
                n = (ps[0] if ps and ps[0] else 1)
                if priv == "?":
                    on = final == "h"
                    for p in ps:
                        if p == 7: self.wrap = on
                        if p in (1049, 47, 1047):
                            if on: self.alt = self.blank(); self.y = self.x = 0
                            elif self.alt is not None: self.alt = None
                    continue
                if priv: continue
                if final in "Hf":
                    self.y = min(self.rows - 1, max(0, (ps[0] if ps else 1) - 1))
                    self.x = min(self.cols - 1, max(0, (ps[1] if len(ps) > 1 else 1) - 1))
                elif final == "A": self.y = max(0, self.y - n)
                elif final == "B": self.y = min(self.rows - 1, self.y + n)
                elif final == "C": self.x = min(self.cols - 1, self.x + n)
                elif final == "D": self.x = max(0, self.x - n)
                elif final == "G": self.x = min(self.cols - 1, n - 1)
                elif final == "d": self.y = min(self.rows - 1, n - 1)
                elif final == "K":
                    mode = ps[0] if ps else 0
                    rng = range(self.x, self.cols) if mode == 0 else range(0, self.x + 1) if mode == 1 else range(self.cols)
                    for c in rng: self.buf[self.y][c] = (" ", None, self.attr["bg"], 0)
                elif final == "J":
                    mode = ps[0] if ps else 0
                    if mode == 2 or mode == 3:
                        for r in range(self.rows): self.buf[r] = [(" ", None, None, 0) for _ in range(self.cols)]
                    elif mode == 0:
                        for c in range(self.x, self.cols): self.buf[self.y][c] = (" ", None, None, 0)
                        for r in range(self.y + 1, self.rows): self.buf[r] = [(" ", None, None, 0) for _ in range(self.cols)]
                elif final == "m": self.sgr(ps, pal)

PARTIAL = re.compile(r"\x1b(?:\[[0-9;?<>=]*[ -/]*|\][^\x07]*|[()])?$")

def record(out, cols, rows, seconds, fps, theme_path, command):
    _, pal = load_theme(theme_path)
    scr = Screen(cols, rows)
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp("sh", ["sh", "-c", command])
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    in_fd = sys.stdin.fileno(); keys_open = True
    frames, pending, carry = [], b"", ""
    start = time.time(); step = 1 / fps; alive = True
    while True:
        due = start + len(frames) * step
        now = time.time()
        if now >= due:
            frames.append([list(r) for r in scr.buf])
            if len(frames) >= seconds * fps: break
            continue
        watch = ([fd] if alive else []) + ([in_fd] if keys_open else [])
        r, _, _ = select.select(watch, [], [], due - now)
        if fd in r:
            try:
                b = os.read(fd, 65536)
            except OSError:
                b = b""
            if not b:
                alive = False
                continue
            pending += b
            try:
                text = pending.decode("utf-8"); pending = b""
            except UnicodeDecodeError as e:
                text = pending[:e.start].decode("utf-8"); pending = pending[e.start:]
            text = carry + text; carry = ""
            m = PARTIAL.search(text)
            if m: carry = text[m.start():]; text = text[:m.start()]
            scr.feed(text, pal)
        if in_fd in r:
            k = os.read(in_fd, 1024)
            if k: os.write(fd, k)
            else: keys_open = False
    try:
        os.kill(pid, 15); os.waitpid(pid, 0)
    except OSError:
        pass
    pickle.dump({"cols": cols, "rows": rows, "theme": theme_path, "frames": frames}, open(out, "wb"))

# ── drawing ───────────────────────────────────────────────────────────────
FONT_SIZE, LINE = 15, 20
BAR, PAD, RADIUS = 34, 12, 11

def find_font(name, fallback):
    dirs = [os.environ.get("FROK_SHOT_FONTS", ""), os.path.expanduser("~/.local/share/fonts")]
    dirs += ["/mnt/c/Users/%s/AppData/Local/Microsoft/Windows/Fonts" % os.environ.get("USER", ""), "/mnt/c/Windows/Fonts"]
    for d in dirs:
        p = os.path.join(d, name)
        if d and os.path.exists(p): return p
    return fallback

REGULAR = ImageFont.truetype(find_font("CaskaydiaCoveNerdFont-Regular.ttf", "DejaVuSansMono.ttf"), FONT_SIZE)
BOLD = ImageFont.truetype(find_font("CaskaydiaCoveNerdFont-Bold.ttf", "DejaVuSansMono-Bold.ttf"), FONT_SIZE)
try: LABEL = ImageFont.truetype("DejaVuSans-Bold.ttf", 12)
except OSError: LABEL = REGULAR
try: SPARE = ImageFont.truetype("DejaVuSansMono.ttf", FONT_SIZE)
except OSError: SPARE = REGULAR
def missing(font):
    """What this font draws for a character it doesn't have."""
    return bytes(font.getmask("\U0010fffe"))
NOTDEF = {id(REGULAR): missing(REGULAR), id(BOLD): missing(BOLD)}
def face(ch, bold):
    f = BOLD if bold else REGULAR
    return SPARE if bytes(f.getmask(ch)) == NOTDEF[id(f)] else f
CELL = round(REGULAR.getlength("M"))
ASCENT = REGULAR.getmetrics()[0]; BASE = (LINE + ASCENT - REGULAR.getmetrics()[1]) // 2

def rgb(h): h = h.lstrip("#"); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
def mix(a, b, w): return tuple(int(round(a[k] * w + b[k] * (1 - w))) for k in range(3))

class Painter:
    """Draws cells through a cache: frames share almost all their glyphs."""
    def __init__(self, theme):
        self.t = theme; self.bg, self.fg = rgb(theme["bg"]), rgb(theme["fg"]); self.tiles = {}

    def tile(self, cell, under):
        ch, f, b, st = cell
        key = (cell, under)
        if key in self.tiles: return self.tiles[key]
        col = rgb(self.bg_hex() if f == "BG" else self.fg_hex() if f == "FG" else f) if f else self.fg
        fill = rgb(self.bg_hex() if b == "BG" else self.fg_hex() if b == "FG" else b) if b else under
        if st & 2: col = mix(col, fill, 0.6)
        im = Image.new("RGB", (CELL, LINE), fill); d = ImageDraw.Draw(im)
        if ch == "█": d.rectangle((0, 0, CELL, LINE), fill=col)
        elif ch == "▄": d.rectangle((0, LINE // 2, CELL, LINE), fill=col)
        elif ch == "▀": d.rectangle((0, 0, CELL, LINE // 2 - 1), fill=col)
        elif ch == "━": d.rectangle((0, LINE // 2 - 1, CELL, LINE // 2), fill=col)
        elif ch != " ": d.text((0, BASE), ch, font=face(ch, st & 1), fill=col, anchor="ls")
        self.tiles[key] = im
        return im

    def bg_hex(self): return self.t["bg"]
    def fg_hex(self): return self.t["fg"]

def window_size(clip):
    return clip["cols"] * CELL + 2 * PAD, clip["rows"] * LINE + 2 * PAD + BAR

def chrome(clip, theme, title):
    """The window around the terminal, and the mask that rounds its corners."""
    w, h = window_size(clip); ui = theme["ui"]
    im = Image.new("RGB", (w, h), rgb(theme["bg"])); d = ImageDraw.Draw(im)
    d.rectangle((0, 0, w, BAR - 1), fill=rgb(ui["surface"]))
    d.line((0, BAR - 1, w, BAR - 1), fill=rgb(ui["border"]))
    for k, c in enumerate(("#ff5f57", "#febc2e", "#28c840")):
        d.ellipse((14 + k * 20, BAR // 2 - 6, 26 + k * 20, BAR // 2 + 6), fill=rgb(c))
    d.text((w // 2, BAR // 2), title, font=LABEL, fill=rgb(ui["muted"]), anchor="mm")
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), RADIUS, fill=255)
    return im, mask

def draw_frame(rows, painter, base, under=None):
    """One frame of a clip on a copy of its window. `under` is a background image
    the size of the terminal area, showing through cells with no colour of their own."""
    im = base.copy()
    if under is None:
        for y, row in enumerate(rows):
            for x, cell in enumerate(row):
                if cell != (" ", None, None, 0):
                    im.paste(painter.tile(cell, painter.bg), (PAD + x * CELL, BAR + PAD + y * LINE))
        return im
    im.paste(under, (0, BAR))
    # over an image, text is drawn with no cell background
    for y, row in enumerate(rows):
        for x, cell in enumerate(row):
            ch, f, b, st = cell
            if ch == " " and not b: continue
            px, py = PAD + x * CELL, BAR + PAD + y * LINE
            if b or ch in "█▄▀━":
                im.paste(painter.tile(cell, painter.bg), (px, py))
            else:
                c = rgb(f) if f and f not in ("BG", "FG") else painter.fg
                if st & 2: c = mix(c, painter.bg, 0.6)
                ImageDraw.Draw(im).text((px, py + BASE), ch, font=face(ch, st & 1), fill=c, anchor="ls")
    return im

def effect_frames(name, opacity, theme, size, count, fps):
    """`count` frames of a real frok background, shown at `opacity` over the theme, as a terminal does."""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "backgrounds"))
    import importlib
    from frokbg.common import Theme
    s = importlib.import_module(f"frokbg.{name}").spec(Theme(theme["fg"], theme["ui"]["accent"], theme["ui"]["accent2"], theme["bg"]))
    bg = Image.new("RGB", size, rgb(theme["bg"]))
    frames = []
    for k in range(count):
        i = int(k * 1000 / fps / s.duration_ms) % s.frames
        f = s.draw(i / s.frames, i).convert("RGB")
        scale = max(size[0] / f.width, size[1] / f.height)
        f = f.resize((int(f.width * scale) + 1, int(f.height * scale) + 1), Image.BILINEAR)
        x, y = (f.width - size[0]) // 2, (f.height - size[1]) // 2
        f = f.crop((x, y, x + size[0], y + size[1]))
        frames.append(Image.blend(bg, f, opacity))
    return frames

def encode(out, frames, fps, colours=128):
    """RGBA frames to a looping GIF: one palette for the whole film, no dithering
    (flat terminal colours stay flat), and each frame stores only the pixels that
    changed. Far-apart changes (the pet, a clock) cost only their own pixels."""
    frames = list(frames)
    w, h = frames[0].size
    sample = frames[:: max(1, len(frames) // 16)]
    mosaic = Image.new("RGB", (w, h * len(sample)))
    for k, f in enumerate(sample): mosaic.paste(f.convert("RGB"), (0, k * h))
    colours = min(colours, 255)                       # index 255 means "transparent"
    palette = mosaic.quantize(colors=colours, method=Image.Quantize.MEDIANCUT)
    pal_bytes = palette.getpalette()[: colours * 3] + [0, 0, 0] * (256 - colours)
    as_l = lambda p: Image.frombytes("L", p.size, p.tobytes())
    clear = Image.new("L", (w, h), 255)
    shapes, last, out_frames = None, None, []
    for f in frames:
        alpha = f.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
        cur = as_l(f.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE))
        cur = Image.composite(cur, clear, alpha)
        if last is None: keep = cur
        else:
            changed = ImageChops.difference(cur, last).point(lambda v: 255 if v else 0)
            keep = Image.composite(cur, clear, changed)
        last = cur
        q = Image.frombytes("P", (w, h), keep.tobytes()); q.putpalette(pal_bytes)
        out_frames.append(q)
    tmp = out + ".tmp.gif"
    out_frames[0].save(tmp, save_all=True, append_images=out_frames[1:], duration=round(1000 / fps),
                       loop=0, optimize=False, disposal=1, transparency=255)
    os.replace(tmp, out)

def stays_private(clip, title):
    """These GIFs are public: stop if a frame names this machine or whoever made
    it. FROK_SHOT_BANNED adds more words."""
    banned = [os.environ.get("USER", ""), os.path.expanduser("~"), os.uname().nodename]
    banned += os.environ.get("FROK_SHOT_BANNED", "").split()
    seen = {"".join(c[0] for c in row) for frame in clip["frames"] for row in frame}
    for line in seen:
        for word in banned:
            if word and word.lower() in line.lower():
                sys.exit(f"term2gif: {title}: a frame shows {word!r}: {line.strip()}")

def gif(argv):
    out, fps = argv[0], float(argv[1]); args = argv[2:]
    grid, backgrounds, parts, colours, skip = 0, [], [], 128, 0
    while args:
        a = args.pop(0)
        if a == "--grid": grid = int(args.pop(0))
        elif a == "--background": backgrounds.append(args.pop(0))
        elif a == "--colours": colours = int(args.pop(0))
        elif a == "--skip": skip = int(float(args.pop(0)) * fps)
        else: parts.append(a.split(":", 1))
    clips = [(pickle.load(open(p, "rb")), title) for p, title in parts]
    for clip, title in clips:
        stays_private(clip, title)
        del clip["frames"][:skip]
    blank = lambda frame: all(c[0] == " " for r in frame for c in r)
    for clip, _ in clips:                             # before the program drew, after it quit
        while len(clip["frames"]) > 1 and blank(clip["frames"][0]): clip["frames"].pop(0)
        while len(clip["frames"]) > 1 and blank(clip["frames"][-1]): clip["frames"].pop()

    def film(k):
        """Every frame of clip k, as RGBA in its window."""
        clip, title = clips[k]
        theme, _ = load_theme(clip["theme"])
        base, mask = chrome(clip, theme, title); painter = Painter(theme)
        under = None
        if backgrounds:
            name, opacity = backgrounds[k].split(":")
            w, h = window_size(clip)
            under = effect_frames(name, float(opacity), theme, (w, h - BAR), len(clip["frames"]), fps)
        for i, rows in enumerate(clip["frames"]):
            im = draw_frame(rows, painter, base, under[i] if under else None).convert("RGBA")
            im.putalpha(mask)
            yield im

    if not grid:
        size = (max(window_size(c)[0] for c, _ in clips), max(window_size(c)[1] for c, _ in clips))
        frames = (f for k in range(len(clips)) for f in film(k))
        def padded():
            for f in frames:
                if f.size == size: yield f
                else:
                    g = Image.new("RGBA", size, (0, 0, 0, 0)); g.alpha_composite(f); yield g
        encode(out, padded(), fps, colours)
        return
    # side by side: all clips play at once, a short last row centred
    gap = 18; w, h = window_size(clips[0][0]); rows = (len(clips) + grid - 1) // grid
    W, H = grid * w + (grid - 1) * gap, rows * h + (rows - 1) * gap
    films = [film(k) for k in range(len(clips))]
    def sheets():
        for tiles in zip(*films):
            sheet = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            for k, t in enumerate(tiles):
                r, c = divmod(k, grid); n = min(grid, len(tiles) - r * grid)
                x = (W - n * w - (n - 1) * gap) // 2 + c * (w + gap)
                sheet.alpha_composite(t, (x, r * (h + gap)))
            yield sheet
    encode(out, sheets(), fps, colours)

if __name__ == "__main__":
    a = sys.argv[1:]
    if a[0] == "record":
        record(a[1], int(a[2]), int(a[3]), float(a[4]), float(a[5]), a[6], a[7])
    elif a[0] == "gif":
        gif(a[1:])
    else:
        sys.exit(__doc__)

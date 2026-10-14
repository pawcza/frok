#!/usr/bin/env python3
"""term2png — replay a terminal capture and draw its final screen as a PNG.

Feeds the bytes from `script` through a tiny terminal emulator (cursor moves,
SGR colours incl. 256/truecolour, alternate screen, autowrap), then renders the
screen as HTML in a window frame coloured by a frok theme and screenshots it
with headless Chrome. No dependencies beyond Python and Chrome (Pillow, if
present, trims the margins).

  term2png.py <capture> <cols> <rows> <theme.json> <title> <out.png> [--stop-at-alt-exit]
"""
import html, json, os, re, shutil, subprocess, sys, tempfile

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
    def __init__(self, cols, rows, stop_at_alt_exit):
        self.cols, self.rows, self.stop = cols, rows, stop_at_alt_exit
        self.main = self.blank(); self.alt = None
        self.y = self.x = 0; self.saved = (0, 0)
        self.attr = self.reset(); self.wrap = True; self.done = False

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

    def feed(self, data, pal):
        token = re.compile(r"\x1b\[([?<>=]?)([0-9;]*)([ -/]*)([@-~])|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b([78=>]|[()].)|([^\x1b])", re.S)
        for m in token.finditer(data):
            if self.done: return
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
                            elif self.alt is not None:
                                if self.stop: self.done = True; return
                                self.alt = None
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

BLOCKS = {"█": "linear-gradient({c},{c})", "▄": "linear-gradient(transparent 50%,{c} 50%)", "▀": "linear-gradient({c} 50%,transparent 50%)"}

def render_html(scr, theme, title, font_css):
    bg, fg = theme["bg"], theme["fg"]; ui = theme["ui"]
    rows = []
    for line in scr.buf:
        out = []
        for ch, f, b, st in line:
            col = {"BG": bg, "FG": fg}.get(f, f) or fg
            bgc = {"BG": bg, "FG": fg}.get(b, b)
            style = []
            if ch in BLOCKS:                       # block elements fill the cell exactly, like a terminal
                layers = [BLOCKS[ch].format(c=col)] + ([f"linear-gradient({bgc},{bgc})"] if bgc else [])
                style.append("background:" + ",".join(layers)); ch = " "
            else:
                if col != fg: style.append(f"color:{col}")
                if bgc: style.append(f"background:{bgc}")
                if st & 1: style.append("font-weight:700")
                if st & 2: style.append("opacity:.6")
            out.append(f'<span style="{";".join(style)}">{html.escape(ch)}</span>' if style else html.escape(ch))
        rows.append('<div class="r">' + "".join(out) + "</div>")
    return f"""<!doctype html><meta charset="utf-8"><style>
{font_css}
html,body{{margin:0;background:transparent}}
body{{padding:48px;display:inline-block}}
.win{{background:{bg};border:1px solid {ui['border']};border-radius:12px;overflow:hidden;
     box-shadow:0 24px 64px rgba(0,0,0,.45),0 4px 14px rgba(0,0,0,.3);display:inline-block}}
.bar{{height:38px;display:flex;align-items:center;gap:8px;padding:0 16px;background:{ui['surface']};
     border-bottom:1px solid {ui['border']};font:600 13px system-ui,sans-serif;color:{ui['muted']}}}
.dot{{width:12px;height:12px;border-radius:50%}}
.title{{flex:1;text-align:center;margin-right:52px}}
.term{{padding:14px 18px 18px;font:15px/1.3 'Term',monospace;color:{fg};white-space:pre}}
.r{{height:1.3em}} .r span{{display:inline-block;height:1.3em;vertical-align:top}}
</style><div class="win"><div class="bar"><span class="dot" style="background:#ff5f57"></span>
<span class="dot" style="background:#febc2e"></span><span class="dot" style="background:#28c840"></span>
<span class="title">{html.escape(title)}</span></div><div class="term">{''.join(rows)}</div></div>"""

def font_css():
    dirs = [os.environ.get("FROK_SHOT_FONTS", ""), os.path.expanduser("~/.local/share/fonts"),
            "/mnt/c/Users/%s/AppData/Local/Microsoft/Windows/Fonts" % os.environ.get("USER", ""), "/mnt/c/Windows/Fonts"]
    for d in dirs:
        reg = os.path.join(d, "CaskaydiaCoveNerdFont-Regular.ttf")
        if d and os.path.exists(reg):
            css = f"@font-face{{font-family:Term;src:url('file://{reg}');font-weight:400}}"
            bold = os.path.join(d, "CaskaydiaCoveNerdFont-Bold.ttf")
            if os.path.exists(bold): css += f"@font-face{{font-family:Term;src:url('file://{bold}');font-weight:700}}"
            return css
    return "@font-face{font-family:Term;src:local('Cascadia Code'),local('JetBrains Mono'),local('DejaVu Sans Mono')}"

def chrome():
    for c in ("google-chrome", "chromium", "chromium-browser"):
        if shutil.which(c): return c
    sys.exit("term2png: needs Chrome or Chromium for the screenshot")

def main():
    a = sys.argv[1:]
    stop = "--stop-at-alt-exit" in a; a = [x for x in a if not x.startswith("--")]
    cap, cols, rows, theme_path, title, out = a[0], int(a[1]), int(a[2]), a[3], a[4], a[5]
    theme, pal = load_theme(theme_path)
    scr = Screen(cols, rows, stop)
    scr.feed(open(cap, "rb").read().decode("utf-8", "replace"), pal)
    with tempfile.TemporaryDirectory() as tmp:
        page = os.path.join(tmp, "shot.html")
        open(page, "w").write(render_html(scr, theme, title, font_css()))
        w, h = cols * 10 + 200, rows * 21 + 220            # roomy; trimmed below
        subprocess.run([chrome(), "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
                        "--force-device-scale-factor=2", "--default-background-color=00000000",
                        f"--window-size={w},{h}", f"--screenshot={os.path.abspath(out)}", "file://" + page],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:                                                    # trim the transparent margin, keep room for the shadow
        from PIL import Image
        im = Image.open(out); box = im.getbbox()
        if box:
            pad = 40
            im.crop((max(0, box[0] - pad), max(0, box[1] - pad), min(im.width, box[2] + pad), min(im.height, box[3] + pad))).save(out, optimize=True)
    except ImportError:
        pass

if __name__ == "__main__":
    main()

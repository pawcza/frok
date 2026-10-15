"""python3 -m frokbg <effect> <out.gif> --fg #hex --accent #hex --accent2 #hex --bg #hex"""
import argparse, importlib, sys, time
from . import EFFECTS, VERSION
from .common import Theme, write_gif

def main():
    ap = argparse.ArgumentParser(prog="frokbg", description=__doc__)
    ap.add_argument("effect", nargs="?", choices=EFFECTS)
    ap.add_argument("out", nargs="?")
    ap.add_argument("--fg", default="#c0caf5")
    ap.add_argument("--accent", default="#7aa2f7")
    ap.add_argument("--accent2", default="#bb9af7")
    ap.add_argument("--bg", default="#1a1b26")
    ap.add_argument("--version", action="store_true", help="print the generator version")
    ap.add_argument("--list", action="store_true", help="list the effects")
    a = ap.parse_args()
    if a.version: print(VERSION); return
    if a.list: print("\n".join(EFFECTS)); return
    if not a.effect or not a.out: ap.error("need an effect and an output file")
    mod = importlib.import_module(f".{a.effect}", __package__)
    start = time.time()
    spec = mod.spec(Theme(a.fg, a.accent, a.accent2, a.bg))
    size = write_gif(a.out, spec)
    print(f"{a.effect}: {spec.width}x{spec.height}, {spec.frames} frames, "
          f"{size / 1e6:.1f} MB, {time.time() - start:.0f}s", file=sys.stderr)

main()

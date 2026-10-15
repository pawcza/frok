# Backgrounds

Animated terminal backgrounds, drawn in the theme's colours. `frok background
<effect>` picks one; frok generates it once per theme (under a minute) and
keeps it in `~/.local/state/frok/backgrounds/<effect>-<theme>-v<version>.gif`.

| Effect | | Size, time* |
|---|---|---|
| `rain` | digital rain in three depths, glowing heads, katakana when a CJK font is installed | 990×660, 220 frames · ~8 MB · ~30 s |
| `starfield` | stars drifting past in three depths, a few twinkling, the odd shooting star | 990×660, 300 frames · ~3 MB · ~20 s |
| `snow` | soft flakes in three depths, swaying in a gentle wind | 990×660, 300 frames · ~7 MB · ~20 s |
| `aurora` | slow curtains of light in the theme's two accents | 480×320, 150 frames · ~5 MB · ~15 s |
| `synthwave` | a neon grid rolling toward a striped sun | 960×640, 60 frames · ~6 MB · ~25 s |

\* on a 12-thread laptop; sizes vary a little per theme.

## Running it yourself

```sh
PYTHONPATH=backgrounds python3 -m frokbg starfield out.gif \
  --fg '#c0caf5' --accent '#7aa2f7' --accent2 '#bb9af7' --bg '#1a1b26'
PYTHONPATH=backgrounds python3 -m frokbg --list       # the effects
```

Only Pillow is needed (frok installs it when you pick a background).

## Adding an effect

One module in `frokbg/` with a `spec(theme)` that returns a `common.Spec`:
the tile size, the frame count, the frame duration and `draw(t, i)`, which
draws the frame at loop position `t` (0 to 1). Add its name to `EFFECTS` in
`frokbg/__init__.py`.

- **Make it loop.** Build every motion from whole cycles over the loop:
  `common.wave(t, cycles, phase)`, or a shift by exactly one repeat of a
  pattern. Then the last frame flows into the first.
- **Make it tile.** WezTerm repeats the tile, so anything crossing an edge
  should come back in on the other side.
- **Draw it on near-black** (`theme.black`): frok shows backgrounds at about
  20%, over the theme's own background.
- **Keep it under about 8 MB.** The frame count matters most. Effects that
  are mostly still can set `delta=True` (each frame stores only what changed);
  soft effects can render small and let the terminal stretch them.

Bump `VERSION` in `frokbg/__init__.py` when you change an effect, so cached
GIFs are regenerated.

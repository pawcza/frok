"""frokbg — frok's animated terminal backgrounds.

Each effect is a module with a `render(theme)` generator spec (see common.py)
that draws one frame for a loop position t in [0, 1). Every motion in an
effect is periodic in t, so the last frame flows straight into the first and
the GIF loops without a seam.
"""
VERSION = 2          # bump when an effect changes: frok regenerates cached GIFs
EFFECTS = ("rain", "starfield", "snow", "aurora", "synthwave")

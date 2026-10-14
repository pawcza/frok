# Companion pets

One file per pet, loaded by `parts/pet.zsh`. `frok companion <name>` picks one.

- `PET_ART`: 6 rows, at most 28 wide. `{1}` `{2}` are the eyes (one character
  each), `{m}` the mouth. Rows 1-3 keep columns 1-9 empty: speech bubbles and
  props are drawn there.
- `PET_ALT` (optional): a second frame, shown while `alt=1`.
- `PET_EYE`: the open eye. `PET_MOUTH`: every expression the engine asks for
  (rest talk open sad happy tongue grit angry), all the same width.
- `PET_TRICKS`: `key:trick:frames`, in footer order. The engine knows
  wink googly look roll yay dead dizzy nap tongue; anything else is the pet's
  own and goes in `pet_trick`.
- `PET_IDLE`: tricks it does by itself when nothing's happening.
- `pet_trick <trick>` (return 1 if it isn't yours), `pet_start <trick>` and
  `pet_frame` (every frame) set the engine's locals: `e1 e2 mouth bub bc
  marg[1-3] mc[1-3] shx fc alt dy hide`. `left` is the trick's frames to go.

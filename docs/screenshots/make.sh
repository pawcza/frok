#!/usr/bin/env zsh
# make.sh — regenerate the README screenshots in docs/img from a demo state
# (made-up sessions, stats and limits; nothing from your machine). Needs
# python3 and Chrome; uses CaskaydiaCove Nerd Font when it can find it.
emulate -L zsh; setopt err_return
HERE=${0:A:h}; FROK=${HERE:h:h}; OUT=${HERE:h}/img; THEME=$FROK/themes/tokyo-night.json
mkdir -p $OUT
D=$(mktemp -d); trap "rm -rf $D" EXIT
UI=$(jq -r '"\(.ui.hover) \(.ui.border) \(.ui.accent) \(.fg) \(.ui.muted)"' $THEME)

# shot <name> <cols> <rows> <title> <command> [keys…]  — run, feed keys, capture, render
shot() {
  local name=$1 cols=$2 rows=$3 title=$4 cmd=$5; shift 5
  { sleep 1.2; for k; do printf %s $k; sleep 0.6; done; sleep 1.5 } |
    script -qc "stty rows $rows cols $cols; $cmd" /dev/null > $D/$name.cap 2>&1 || true
  python3 $HERE/term2png.py $D/$name.cap $cols $rows $THEME "$title" $OUT/$name.png
  print "  $OUT/$name.png"
}

# ── demo state ──────────────────────────────────────────────────────────
S=$D/state/companion; mkdir -p $S/sessions $S/status $S/stats $D/gen
US=$'\x1f'; now=$(date +%s)
sess() {  # sess <id> <age s> <state> <tty> <detail> <title> <ctx%>
  print -r -- "$(( now - $2 ))$US$3$US$4$US/home/you/dev$US$5$US$6$US" > $S/sessions/$1
  print -r -- "$now$US$7$US$US$US$US$US" > $S/status/$1
}
sess s1 4    working  t:pts/91 'Edit src/auth/refresh.ts'             'Fix the token refresh race'          34
sess s2 70   waiting  t:pts/92 'needs permission: $ npm run migrate'  'Add dark mode to the settings page'  61
sess s3 9    thinking t:pts/93 '“why does the build cache miss?”'     'Speed up the Docker build'           18
sess s4 200  done     t:pts/94 'finished'                             'Move CI to a self-hosted runner'     82
sess s5 900  done     t:pts/95 'finished'                             'Write the release notes'             9
sess s6 3400 idle     t:pts/96 'session started'                      'Tidy up the README'                  3
print -r -- "$now${US}34${US}27$US$(( now + 2*3600 + 840 ))${US}46$US$(( now + 3*86400 ))${US}personal" > $S/status/s1
jq -n --arg t $(date +%F) '[range(0; 30)] | map({key: ((now - . * 86400) | strftime("%Y-%m-%d")),
  value: {tok: (180000000 + (. * 7919 % 23) * 9000000), add: (900 + (. * 131 % 17) * 120), del: (200 + (. * 37 % 11) * 40), commits: (4 + . % 6)}}) | from_entries' > $S/stats/days.json
print -r -- 'Alt + D=split →;Alt + Shift + D=split ↓;Alt + ← / ↑ / ↓ / →=move;Ctrl + Shift + W=close pane' > $D/gen/keys.txt

COMP="env -u FROK_PANE FROK_DEMO=1 FROK_DEMO_FOCUS=t:pts/91 FROK_STATE=$D/state FROK_GEN=$D/gen FROK_UI='$UI' \
  FROK_DEMO_FACT='An octopus has three hearts, and two of them stop when it swims.' timeout -s KILL 4 zsh $FROK/companion/companion.zsh"

print "screenshots:"
shot companion 128 16 "frok — companion" "FROK_PET=frok $COMP"

# every pet, mid-trick
for pk in frok:f cat:k ghost:b robot:b octopus:j; do
  shot pet-${pk%%:*} 33 8 "${pk%%:*}" "FROK_PET=${pk%%:*} ${COMP/timeout -s KILL 4/timeout -s KILL 3}" ${pk#*:}
done
python3 - $OUT <<'PY'
import sys
from PIL import Image
out = sys.argv[1]; names = ["frok", "cat", "ghost", "robot", "octopus"]
ims = [Image.open(f"{out}/pet-{n}.png") for n in names]
W = sum(i.width for i in ims) - 60 * (len(ims) - 1); H = max(i.height for i in ims)
g = Image.new("RGBA", (W, H), (0, 0, 0, 0)); x = 0
for i in ims: g.alpha_composite(i.convert("RGBA"), (x, (H - i.height) // 2)); x += i.width - 60
g.save(f"{out}/pets.png", optimize=True)
PY
rm -f $OUT/pet-*.png; print "  $OUT/pets.png"

# the settings menu and the theme list, on a clean config
mkdir -p $D/cfg
shot menu 96 24 "frok menu" "FROK_CONFIG_DIR=$D/cfg FROK_STATE=$D/state timeout -s KILL 4 $FROK/bin/frok menu"

# the companion in every theme
themes=(tokyo-night catppuccin-mocha dracula gruvbox-dark matrix)
for th in $themes; do
  THEME=$FROK/themes/$th.json
  UI=$(jq -r '"\(.ui.hover) \(.ui.border) \(.ui.accent) \(.fg) \(.ui.muted)"' $THEME)
  COMP="env -u FROK_PANE FROK_DEMO=1 FROK_DEMO_FOCUS=t:pts/91 FROK_STATE=$D/state FROK_GEN=$D/gen FROK_UI='$UI' timeout -s KILL 3 zsh $FROK/companion/companion.zsh"
  shot theme-$th 84 8 "$(jq -r .name $THEME)" "FROK_PET=frok $COMP" >/dev/null
done
python3 - $OUT $themes <<'PY'
import sys
from PIL import Image
out, names = sys.argv[1], sys.argv[2:]
ims = [Image.open(f"{out}/theme-{n}.png").convert("RGBA") for n in names]
w, h = ims[0].size; ov = 70                   # overlap the shadow margins
cols = 2; rows = (len(ims) + 1) // 2
g = Image.new("RGBA", (cols * w - (cols - 1) * ov, rows * h - (rows - 1) * ov), (0, 0, 0, 0))
for k, im in enumerate(ims):
    r, c = divmod(k, cols)
    x = c * (w - ov) if not (k == len(ims) - 1 and len(ims) % 2) else (g.width - w) // 2
    g.alpha_composite(im, (x, r * (h - ov)))
g.save(f"{out}/themes.png", optimize=True)
PY
rm -f $OUT/theme-*.png; print "  $OUT/themes.png"

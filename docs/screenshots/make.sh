#!/usr/bin/env zsh
# make.sh: regenerate the README's GIFs in docs/img from real runs of the
# companion and `frok menu`, on a staged demo state (made-up sessions, stats and
# limits; nothing from your machine). Needs python3 with Pillow and jq; uses
# CaskaydiaCove Nerd Font when it can find it.
#   docs/screenshots/make.sh                 all of them
#   docs/screenshots/make.sh companion pets  just those
emulate -L zsh; setopt err_return
HERE=${0:A:h}; FROK=${HERE:h:h}; OUT=${HERE:h}/img
mkdir -p $OUT
D=$(mktemp -d); trap "rm -rf $D" EXIT
T2G=(python3 $HERE/term2gif.py)
FPS=6

ui_of() { jq -r '"\(.ui.hover) \(.ui.border) \(.ui.accent) \(.fg) \(.ui.muted)"' $FROK/themes/$1.json; }

# ── demo state ──────────────────────────────────────────────────────────
S=$D/state/companion; mkdir -p $S/sessions $S/status $S/stats $S/widgets $D/gen
US=$'\x1f'; now=$(date +%s)
sess() {  # sess <id> <age s> <state> <tty> <detail> <title> <ctx%> <agent>
  print -r -- "$(( $(date +%s) - $2 ))$US$3$US$4$US/home/you/dev$US$5$US$6$US$US$8" >| $S/sessions/$1
  [[ -n $7 ]] && print -r -- "$now$US$7$US$US$US$US$US" >| $S/status/$1
  return 0
}
stage() {   # the opening scene, before a recording starts
  rm -f $S/sessions/*(N) $S/status/*(N)
  sess s1 4    working  t:pts/91 'Edit src/auth/refresh.ts'          'Fix the token refresh race'          34 claude
  sess s2 9    thinking t:pts/92 '“add a migration for the table”'   'Add dark mode to the settings page'  ""  codex
  sess s3 6    working  t:pts/93 '$ docker build -t app .'           'Speed up the Docker build'           ""  gemini
  sess s4 12   thinking t:pts/94 '“why does CI time out?”'           'Move CI to a self-hosted runner'     ""  opencode
  print -r -- "$now$US${US}27$US$(( now + 2*3600 + 840 ))${US}46$US$(( now + 3*86400 ))${US}demo" >| $S/status/limits
}
jq -n '[range(0; 30)] | map({key: ((now - . * 86400) | strftime("%Y-%m-%d")),
  value: {tok: (180000000 + (. * 7919 % 23) * 9000000), add: (900 + (. * 131 % 17) * 120), del: (200 + (. * 37 % 11) * 40), commits: (4 + . % 6)}}) | from_entries' > $S/stats/days.json
print -r -- 'Alt + D=split →;Alt + Shift + D=split ↓;Alt + ← / ↑ / ↓ / →=move;Ctrl + Shift + W=close pane' > $D/gen/keys.txt
print -r -- '{"dashboard":["clock","weather","news","timer","fact","stats","limits","keys","tricks"],
  "widgets":{"weather":{"city":"Lisbon"},"clock":{"zones":"Tokyo=Asia/Tokyo, New York=America/New_York"}}}' > $D/frok.json
print -r -- '{"dashboard":["clock","fact","stats","limits","tricks"],"widgets":{"clock":{"zones":"Tokyo=Asia/Tokyo"}}}' > $D/short.json
print -r -- '{"city":"Lisbon","units":"metric","place":"Lisbon","current":{"temperature_2m":21.2,"apparent_temperature":21,"weather_code":1,"wind_speed_10m":14},
  "current_units":{"wind_speed_10m":"km/h"},"daily":{"temperature_2m_max":[24],"temperature_2m_min":[16],"precipitation_probability_max":[5]}}' > $S/widgets/weather.json
print -r -- "HN"$'\t'"Show HN: A terminal pet that keeps an eye on your builds"$'\t'"https://example.com" > $S/widgets/news.tsv
print -r -- "$(( now - 8 * 60 )) 1500 focus" > $S/widgets/timer
mkdir -p $D/home

# companion <theme> <cfg> <pet> <seconds> → the command line that runs the real companion on the demo state
companion() {
  print -r -- "env -u FROK_PANE -u WEZTERM_PANE -u KITTY_WINDOW_ID HOME=$D/home FROK_DEMO=1 FROK_DEMO_FOCUS=t:pts/91 FROK_STATE=$D/state FROK_GEN=$D/gen FROK_CFG=$2 \
FROK_UI='$(ui_of $1)' FROK_PET=$3 FROK_DEMO_FACT='An octopus has three hearts, and two of them stop when it swims.' \
timeout --foreground -s KILL $(( $4 + 1 )) zsh $FROK/companion/companion.zsh"
}
# rec <clip> <cols> <rows> <seconds> <theme> <command>: keys and state changes come from stdin's writer
rec() { $T2G record $D/$1.clip $2 $3 $4 $FPS $FROK/themes/$5.json "stty rows $3 cols $2; $6"; }

# ── the scenes ──────────────────────────────────────────────────────────
scene_companion() {    # sessions change, the pet reacts
  stage
  { sleep 3.0; sess s2 0 waiting t:pts/92 'needs permission: $ npm run migrate' 'Add dark mode to the settings page' "" codex
    sleep 3.2; sess s2 0 working t:pts/92 '$ npm run migrate' 'Add dark mode to the settings page' "" codex
    sleep 1.4; sess s3 0 done t:pts/93 'finished' 'Speed up the Docker build' "" gemini
    sleep 2.6; sess s1 0 error t:pts/91 'failed: $ npm test' 'Fix the token refresh race' 41 claude
    sleep 3.0; sess s1 0 working t:pts/91 'Edit src/auth/refresh.test.ts' 'Fix the token refresh race' 47 claude
    sleep 1.8; print -n p
    sleep 1.4; sess s1 0 done t:pts/91 'finished' 'Fix the token refresh race' 52 claude
    sess s2 0 done t:pts/92 'finished' 'Add dark mode to the settings page' "" codex
    sess s4 0 done t:pts/94 'finished' 'Move CI to a self-hosted runner' "" opencode
    sleep 4; } | rec companion 124 20 22 tokyo-night "$(companion tokyo-night $D/frok.json frok 22)"
  $T2G gif $OUT/companion.gif $FPS $D/companion.clip:"frok companion" --colours 96
}

scene_pets() {         # every pet running through its tricks
  local p keys k t; local -a clips
  stage
  for p in frok cat ghost robot octopus; do
    keys=$(zsh -c 'source $1; for t in $PET_TRICKS; do print -n ${t%%:*}; done' _ $FROK/companion/pets/$p.zsh)
    { sleep 1; for k in ${(s::)keys}; do printf %s $k; sleep 2.6; done; sleep 12; } |
      rec pet-$p 33 8 12 tokyo-night "$(companion tokyo-night $D/short.json $p 12)" || true
    clips+=($D/pet-$p.clip:$p)
  done
  $T2G gif $OUT/pets.gif $FPS --grid 3 $clips --colours 48
}

scene_menu() {         # moving through `frok menu`, then picking a theme with its live preview
  mkdir -p $D/cfg; print -r -- '{"terminals":["kitty"],"configured":true}' > $D/cfg/frok.json
  local down=$'\e[B' up=$'\e[A' enter=$'\r'
  { sleep 2.6
    for k in $down $down $down $down $up $up $up $up; do printf %s $k; sleep 0.55; done
    sleep 0.5; printf %s $enter; sleep 1.2
    for k in $down $down $down $up; do printf %s $k; sleep 1.0; done
    printf %s $'\e'; sleep 2.2; printf q; sleep 1; } |
    rec menu 92 30 14.6 tokyo-night "env HOME=$D/home FROK_CONFIG_DIR=$D/cfg FROK_STATE=$D/state timeout --foreground -s KILL 16 $FROK/bin/frok menu"
  $T2G gif $OUT/menu.gif $FPS --skip 2.2 $D/menu.clip:"frok menu" --colours 64
}

scene_themes() {       # the same companion, theme after theme
  local th; local -a clips
  stage
  for th in tokyo-night catppuccin-mocha dracula gruvbox-dark matrix; do
    { sleep 1.1; sess s2 0 waiting t:pts/92 'needs permission: $ npm run migrate' 'Add dark mode to the settings page' "" codex; sleep 2.5; } |
      rec theme-$th 100 13 3 $th "$(companion $th $D/short.json frok 3)" || true
    sess s2 9 thinking t:pts/92 '“add a migration for the table”' 'Add dark mode to the settings page' "" codex
    clips+=("$D/theme-$th.clip:frok theme $th")
  done
  $T2G gif $OUT/themes.gif $FPS $clips --colours 128
}

scene_backgrounds() {  # the five effects, behind a working terminal
  local e FPS=10; local -a clips bgs
  stage
  print -r -- '{"dashboard":["clock"],"widgets":{"clock":{"zones":"Tokyo=Asia/Tokyo"}}}' > $D/tiny.json
  for e in rain starfield snow aurora synthwave; do
    { sleep 3; } | rec bg-$e 104 18 2.6 tokyo-night "$(companion tokyo-night $D/tiny.json frok 3)" || true
    clips+=("$D/bg-$e.clip:frok background $e"); bgs+=(--background $e:0.5)
  done
  $T2G gif $OUT/backgrounds.gif $FPS $bgs $clips --colours 96
}

print "gifs:"
(( $# )) || set -- companion pets menu themes backgrounds
for s; do
  scene_$s; print "  $OUT/$s.gif  $(( $(wc -c < $OUT/$s.gif) / 1024 )) KB"
done

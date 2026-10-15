#!/usr/bin/env zsh
# companion.zsh — the companion pane: an animated pet that watches your Claude
# Code sessions. It finds them in the terminal (parts/panes.zsh), learns what
# each is doing from the hook, the transcript and the status line
# (parts/sessions.zsh), and draws them beside the pet with stats, limits and
# keys below (parts/render.zsh). The pet's mood follows the most urgent session.
# Keys and clicks: parts/input.zsh. Ctrl+C quits.
emulate -L zsh
setopt extendedglob
zmodload zsh/datetime 2>/dev/null
zmodload -F zsh/stat b:zstat 2>/dev/null
HERE=${0:A:h}                       # parts/ and pets/ live next to this script
STATE=${FROK_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/frok}/companion
SDIR="$STATE/sessions"              # written by companion-event.sh

US=$'\x1f'; TAB=$'\t'

# Colours come from the terminal's own ANSI palette, so the companion follows
# the theme; the chips use the frok theme's own colours (FROK_UI).
G=$'\e[32m'; L=$'\e[34m'; D=$'\e[90m'; W=$'\e[39m'
Y=$'\e[33m'; C=$'\e[36m'; R=$'\e[31m'; M=$'\e[35m'; X=$'\e[0m'

# the pieces, in dependency order: the pet and the chips are set up when sourced
for f in panes pet ui sessions widgets render input; do source $HERE/parts/$f.zsh; done
dashboard_load

# hide cursor + SGR mouse reporting (clicks arrive as \e[<b;x;yM). Echo stays
# off for the whole run, otherwise mouse/scroll reports that land between reads
# get printed onto the screen (e.g. "[[<64;70;5M" when scrolling).
STTY_SAVED=$(stty -g 2>/dev/null)
[[ -t 0 ]] && stty -echo -icanon 2>/dev/null
cleanup() { print -n $'\e[?1000l\e[?1006l\e[?25h\e[?7h\e[?1049l'"$X"; [[ -n $STTY_SAVED ]] && stty "$STTY_SAVED" 2>/dev/null; rm -f "$FACTFILE" "$FACTLOCK" 2>/dev/null; exit 0 }
trap cleanup INT TERM
# settings: the companion steps aside for frok's menu, then starts over (a new
# pet, theme or facts setting takes effect)
open_settings() {
  print -n $'\e[?1000l\e[?1006l\e[?25h\e[?7h\e[?1049l'"$X"
  [[ -n $STTY_SAVED ]] && stty "$STTY_SAVED" 2>/dev/null
  rm -f "$FACTFILE" "$FACTLOCK" 2>/dev/null
  trap '' INT                          # Ctrl+C leaves the menu, not the companion
  ${HERE:h}/bin/frok menu
  exec ${HERE:h}/bin/frok companion run
}
print -n $'\e[?1049h\e[2J\e[?25l\e[?7l\e[?1000h\e[?1006h'   # alternate screen: no scrollback

typeset -a prev frogrow; tick=0; lastfact=""
update_size; refresh_panes; refresh_sessions
while true; do
  draw_frame
  # read here, not in a function: zsh holds back the TERM trap while a function
  # waits in read, so the companion wouldn't quit when its pane closes
  if [[ -t 0 ]]; then
    if read -t 0.18 -k 1 -s key 2>/dev/null; then
      buf=$key
      while read -t 0.01 -k 1 -s key 2>/dev/null; do buf+=$key; done   # rest of a multi-byte key / mouse report
      handle_input
    fi
  else
    sleep 0.18
  fi
  (( tick++ ))
done

# background.zsh — the terminal background: digital rain recoloured to the
# theme, or your own image / GIF.

# Path of the current background (generated on first use), or nothing.
background_file() {
  local b=$(cfg .background)
  case $b in
    none|"") return ;;
    rain)
      local f=$FROK_STATE/backgrounds/rain-${T[slug]}.gif
      [[ -f $f ]] || background_make_rain $f >&2 || return
      print -r -- $f ;;
    *) b=$(expand_home $b); [[ -f $b ]] && print -r -- $b || warn "background file $b not found" ;;
  esac
}

background_make_rain() {
  pkg_install python3 pillow >&2
  step "generating the rain for ${T[name]} (about a minute, once per theme)"
  python3 $FROK_HOME/backgrounds/rain_gen.py $1 ${T[fg]} ${T[accent]} $(mix ${T[accent]} ${T[bg]} 22) >/dev/null \
    || { warn "couldn't generate the rain background"; return 1 }
}

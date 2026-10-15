# background.zsh — the terminal background: an animated effect recoloured to
# the theme (backgrounds/frokbg), or your own image / GIF.

BG_PKG=$FROK_HOME/backgrounds

# The effects and the generator version, as the package declares them.
bg_effects() { sed -n 's/^EFFECTS = (\(.*\))/\1/p' $BG_PKG/frokbg/__init__.py | tr -d '",' | tr ' ' '\n' | grep -v '^$'; }
bg_version() { sed -n 's/^VERSION = \([0-9]*\).*/\1/p' $BG_PKG/frokbg/__init__.py; }
bg_is_effect() { (( ${${(f)"$(bg_effects)"}[(Ie)$1]} )); }

# Path of the current background (generated on first use), or nothing.
background_file() {
  local b=$(cfg .background)
  case $b in
    none|"") return ;;
    *)
      if bg_is_effect $b; then
        # one GIF per effect, theme and generator version
        local f=$FROK_STATE/backgrounds/$b-${T[slug]}-v$(bg_version).gif
        [[ -f $f ]] || background_make $b $f >&2 || return
        print -r -- $f
      else
        b=$(expand_home $b); [[ -f $b ]] && print -r -- $b || warn "background file $b not found"
      fi ;;
  esac
}

background_make() {   # background_make <effect> <out.gif>
  pkg_install python3 pillow >&2
  step "generating the $1 background for ${T[name]} (under a minute, once per theme)"
  rm -f $FROK_STATE/backgrounds/$1-${T[slug]}.gif(N) $FROK_STATE/backgrounds/$1-${T[slug]}-v*.gif(N)   # older versions
  PYTHONPATH=$BG_PKG python3 -m frokbg $1 $2 --fg ${T[fg]} --accent ${T[accent]} --accent2 ${T[accent2]} --bg ${T[bg]} 2>/dev/null \
    || { warn "couldn't generate the $1 background"; return 1 }
}

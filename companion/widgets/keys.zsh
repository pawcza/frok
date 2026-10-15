# keys — the settings button and this terminal's pane shortcuts.
W_LABEL[keys]=keys

w_keys_render() {
  local -a items=(",${TAB}settings")                 # frok's own: opens the menu
  local kf=${FROK_GEN:-$HOME/.config/frok/generated}/keys.txt kv p
  [[ -r $kf ]] && for kv in ${(s:;:)"$(<$kf)"}; do items+=("${kv%%=*}$TAB${kv#*=}"); done
  pack $cw "${items[@]}"; wl=("${packed[@]}")
  p=(${(s.:.)packpos[1]}); wclick+=("${p[1]}:${p[2]}:${p[3]}:settings")
}
w_keys_click() { open_settings; }

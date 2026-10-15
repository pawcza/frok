# tricks — the pet's tricks: press its key or click it. Labelled with the pet's name.
w_tricks_init() { W_LABEL[tricks]=$PET_LABEL; }

w_tricks_render() {
  local -a items; local t p
  for t in $PET_TRICKS; do items+=("${t%%:*}$TAB${${t#*:}%%:*}"); done
  pack $cw "${items[@]}"; wl=("${packed[@]}")
  for t in $packpos; do p=(${(s.:.)t}); wclick+=("${p[1]}:${p[2]}:${p[3]}:${p[4]}"); done
}
w_tricks_click() { [[ -z $phase ]] && start_trick ${trickkey[$1]}; }

# theme.zsh — palettes. A theme is one JSON file in themes/ (or
# ~/.config/frok/themes/ for your own); every renderer reads it through T[...].

theme_dirs() { print -l $FROK_HOME/themes $FROK_CONFIG_DIR/themes; }
theme_file() {
  local d; for d in $FROK_CONFIG_DIR/themes $FROK_HOME/themes; do
    [[ -f $d/$1.json ]] && { print $d/$1.json; return }
  done
}
theme_names() { local d f; for d in $(theme_dirs); do for f in $d/*.json(N); do print ${f:t:r}; done; done | sort -u; }

typeset -gA T
# load_theme <name> → T[bg fg cursor selection a0..a7 b0..b7 surface muted accent accent2 border hover name]
load_theme() {
  local f=$(theme_file $1); [[ -n $f ]] || die "no theme called '$1' (try: frok theme)"
  T=()
  local k v
  while IFS=$'\t' read -r k v; do T[$k]=$v; done < <(jq -r '
    ([["name",.name],["bg",.bg],["fg",.fg],["cursor",.cursor],["selection",.selection]]
     + (.ansi | to_entries | map(["a\(.key)", .value]))
     + (.brights | to_entries | map(["b\(.key)", .value]))
     + (.ui | to_entries | map([.key, .value])))[] | @tsv' $f)
  T[slug]=$1
}

# mix <#hex> <#hex> <percent of the first> → #hex
mix() {
  local a=${1#\#} b=${2#\#} w=$3 i out="#"
  for i in 0 2 4; do
    out+=$(printf '%02x' $(( (0x${a:$i:2} * w + 0x${b:$i:2} * (100 - w) + 50) / 100 )))
  done
  print $out
}

# Swatch line for listings: the 8 ANSI colours as blocks, in truecolour.
swatch() {
  local i c out=""
  for i in 0 1 2 3 4 5 6 7; do
    c=${T[a$i]#\#}
    out+=$'\e[48;2;'"$((0x${c:0:2}));$((0x${c:2:2}));$((0x${c:4:2}))m  "
  done
  print -rn -- "$out"$'\e[0m'
}

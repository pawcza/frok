# wizard.zsh — the step-by-step setup in the terminal: a banner, then one
# screen per setting. Each pick is applied straight away so the terminal shows
# it; Enter keeps the highlighted choice and moves on.

zmodload zsh/mathfunc   # int() for the diagrams and previews
WZ_STEPS=6
WZ_R=$'\e[0m' WZ_B=$'\e[1m'
# Nerd Font icons the previews use
WZ_IC_GIT=$'\ue725' WZ_IC_DIR=$'\uf07c' WZ_IC_TERM=$'\uf120' WZ_IC_NODE=$'\ue718' WZ_IC_GH=$'\uf113'

hexfg() { local c=${1#\#}; print -rn -- $'\e[38;2;'"$((0x${c:0:2}));$((0x${c:2:2}));$((0x${c:4:2}))m"; }

wz_cls() { [[ -t 1 ]] && print -n $'\e[2J\e[H'; }

wz_banner() {   # wz_banner [tagline]
  local -a logo=(
    ''
    '██████████  ████████      ██████    ██      ██'
    '██          ██      ██  ██      ██  ██    ██'
    '████████    ████████    ██      ██  ██████'
    '██          ██    ██    ██      ██  ██    ██'
    '██          ██      ██    ██████    ██      ██'
  )
  local -a frog=("${(@f)$(<$FROK_HOME/companions/frok/frog.txt)}")
  local i
  (( ${COLUMNS:-$(tput cols 2>/dev/null || print 80)} < 80 )) && frog=('' '' '' '' '' '')   # the logo alone fits
  print
  for (( i = 1; i <= $#frog; i++ )); do
    print -r -- "  $(hexfg $(mix ${T[accent]} ${T[accent2]} $(( 100 - 100 * (i - 1) / ($#frog - 1) ))))${(r:49:)logo[i]}$(hexfg ${T[a2]})${frog[i]:5}$WZ_R"
  done
  print -r -- $'\n'"  $(hexfg ${T[muted]})${1:-your terminal, set up one step at a time}$WZ_R"
}

# Windows Terminal or not, asked once per run (detecting it goes through cmd.exe, which is slow)
wz_has_wt() {
  [[ -n ${WZ_WT-} ]] || { terminals_active | grep -qx windows-terminal && WZ_WT=1 || WZ_WT=0 }
  (( WZ_WT ))
}

# ── the banner frog, fidgeting while a menu waits for a key ────────────
# Drawn at the banner's position (rows 1-7, column 52), cursor saved and restored.
WZF_T=0 WZF_EV="" WZF_LEFT=0 WZF_FX=10
wz_frog_idle() {
  local -a art=("${(@f)$(<$FROK_HOME/companions/frok/frog.txt)}")
  local e1="'" e2="'" mouth="'-----'" bub="" dx=0 dy=0 fly=-1 Q="'" r out row1 c
  (( WZF_T++ ))
  if (( WZF_LEFT <= 0 )); then
    WZF_EV=""
    if (( RANDOM % 12 == 0 )); then
      local -a tr=(blink wink look googly tongue yay fly hop dance dizzy shiver sleep)
      WZF_EV=${tr[RANDOM % $#tr + 1]}
      case $WZF_EV in
        fly) WZF_LEFT=45; WZF_FX=$(( RANDOM % 20 )) ;;  sleep) WZF_LEFT=40 ;;
        blink) WZF_LEFT=2 ;;  hop|dance) WZF_LEFT=12 ;;  *) WZF_LEFT=14 ;;
      esac
    fi
  fi
  (( WZF_LEFT-- ))
  case $WZF_EV in
    blink)  e1=-; e2=- ;;
    wink)   e1=- ;;
    look)   (( WZF_LEFT > 7 )) && { e1=.; e2=$Q } || { e1=$Q; e2=. } ;;
    googly) e1=O; e2=. ;;
    tongue) mouth="'--p--'"; bub=":P" ;;
    yay)    e1=^; e2=^; mouth="'\___/'"; (( WZF_T % 4 < 2 )) && bub="yay!" || bub="\o/" ;;
    dizzy)  local -a dz=(@ o O o); e1=${dz[WZF_T % 4 + 1]}; e2=${dz[(WZF_T + 2) % 4 + 1]}; bub="~@~" ;;
    shiver) dx=$(( WZF_T % 2 )) ;;
    dance)  dx=$(( (WZF_T / 2) % 2 * 2 )); e1=^; e2=^; bub="♪" ;;
    hop)    (( WZF_LEFT % 6 < 3 )) && dy=1 ;;
    sleep)  e1=-; e2=-; local -a zz=(z zZ zZz); bub=${zz[(WZF_T / 5) % 3 + 1]} ;;
    fly)    if (( WZF_LEFT > 8 )); then
              (( WZF_FX += RANDOM % 3 - 1, WZF_FX < 0 ? (WZF_FX = 0) : 0, WZF_FX > 24 ? (WZF_FX = 24) : 0 ))
              fly=$WZF_FX; e1=o; e2=o
            elif (( WZF_LEFT > 5 )); then mouth="'--O--'"; e1=O; e2=O
            else e1=^; e2=^; mouth="'\___/'"; bub="gulp"; fi ;;
  esac
  for (( r = 1; r <= 6; r++ )); do art[r]=${art[r]:5}; done
  local eA=${art[2]%%$Q*} rest=${art[2]#*$Q}; local eB=${rest%%$Q*} eC=${rest#*$Q}
  art[2]="$eA$e1$eB$e2$eC"
  art[4]=${art[4]/"'-----'"/$mouth}
  row1="${(l:24:)}"
  (( fly >= 0 )) && row1[fly+1]='*'
  [[ -n $bub ]] && row1[18,24]=${(r:7:)bub}
  out=$'\e7'
  for (( r = 1; r <= 7; r++ )); do
    out+=$'\e['"$r;52H"$'\e[K'
    if (( r == 1 && ! dy )); then out+="$(hexfg ${T[accent]})$row1"
    elif (( r - 1 + dy >= 1 && r - 1 + dy <= 6 )); then out+="$(hexfg ${T[a2]})${(l:dx:)}${art[r - 1 + dy]}"; fi
  done
  print -rn -- "$out$WZ_R"$'\e8'
}

hexbg() { local c=${1#\#}; print -rn -- $'\e[48;2;'"$((0x${c:0:2}));$((0x${c:2:2}));$((0x${c:4:2}))m"; }

# visible width of a string with colour codes in it
wz_vis() { local p=${1//$'\e'\[[0-9;]#m/}; print -r -- ${#p}; }

# wz_header <step> <title> <what it's about>   (WZ_SOLO=1: one screen opened from the menu)
# The title sits on a coloured band; a setting with several questions shows them as tabs there.
wz_header() {
  local i dots="" where="step $1 of $WZ_STEPS"
  for (( i = 1; i <= WZ_STEPS; i++ )); do
    (( i <= $1 )) && dots+="$(hexfg ${T[accent]})●" || dots+="$(hexfg ${T[border]})○"
  done
  (( ${WZ_SOLO:-0} )) && { dots=""; where="menu › $2"; }
  wz_cls
  print -r -- $'\n'"  $WZ_B$(hexfg ${T[a2]})frok$WZ_R  ${dots:+$dots$WZ_R  }$(hexfg ${T[muted]})$where$WZ_R"$'\n'
  local -a tl; local act=1 band="$(hexbg ${T[surface]})  "
  if [[ -n ${WZ_TABBAR-} ]]; then tl=("${(@s:|:)WZ_TABBAR}"); act=$WZ_TABI; else tl=($2); fi
  for (( i = 1; i <= $#tl; i++ )); do
    if (( i == act )); then band+="$(hexbg ${T[accent]})$(hexfg ${T[bg]})$WZ_B  ${tl[i]}  $WZ_R$(hexbg ${T[surface]}) "
    else band+="$(hexbg ${T[hover]})$(hexfg ${T[muted]})  ${tl[i]}  $WZ_R$(hexbg ${T[surface]}) "; fi
  done
  (( $#tl > 1 )) && band+=" $(hexfg ${T[muted]})←→"
  print -r -- "$band"$'\e[K'"$WZ_R"
  print -r -- $'\n'"  $(hexfg ${T[muted]})$3$WZ_R"$'\n'
}

# wz_tabs <label|label…> <function…> — a setting with several questions, one tab
# each. A tab function draws its screen and returns 0 (picked: on to the next tab),
# 1 (Esc: leave the setting), 2/3 (←/→), or 4 (doesn't apply right now: skip it).
wz_tabs() {
  local WZ_TABBAR=$1; shift
  local -a fns=("$@"); local WZ_TABI=1 rc dir=1
  while (( WZ_TABI >= 1 && WZ_TABI <= $#fns )); do
    ${fns[WZ_TABI]}; rc=$?
    case $rc in
      0) dir=1; (( WZ_TABI++ )) ;;
      1) return 0 ;;
      2) dir=-1; (( WZ_TABI > 1 )) && (( WZ_TABI-- )) ;;
      3) dir=1; (( WZ_TABI < $#fns )) && (( WZ_TABI++ )) ;;
      4) (( WZ_TABI += dir )); (( WZ_TABI < 1 )) && { WZ_TABI=1; dir=1 } ;;
    esac
  done
}

# wz_choose <default> <value> <description> [<value> <description>…] → the chosen value
# ↑/↓ (or j/k) move, Enter picks, a number jumps to that row, Esc/q keeps the default
# and fails (status 1), so a screen can skip its follow-up questions. Starts on the
# default, which is marked as current. A lone "-" puts a gap in the list.
#   WZ_PREVIEW=<function>  prints a preview of the highlighted value, drawn beside the
#                          list (or under it when the terminal is narrow)
#   WZ_TABS=1              ←/→ leave with status 2/3 so wz_tabs can switch tabs
#   WZ_ESC=<value>         what Esc/q return instead (menus: nothing is "current")
#   WZ_HINT=<text>         replaces the help line
#   WZ_IDLE=<function>     runs every 0.12s while no key is pressed (the menu's frog)
wz_choose() {
  local def=$1; shift
  local -a vals descs gaps; while (( $# )); do
    [[ $1 == - ]] && { gaps+=($#vals); shift; continue }
    vals+=($1); descs+=("$2"); shift 2
  done
  local i w=0 nw=${#${#vals}} sel=${vals[(Ie)$def]} key num="" up=0
  (( sel )) || sel=1
  for i in $vals; do (( $#i > w )) && w=$#i; done
  local acc=$(hexfg ${T[accent]}) mut=$(hexfg ${T[muted]})
  local hint="↑↓ to move, Enter to pick" cur=$def cols=80 sz
  sz=$(stty size </dev/tty 2>/dev/null) && cols=${sz##* }
  (( ${WZ_TABS:-0} )) && hint+=" · ←→ switch tabs"
  (( ${WZ_SOLO:-0} )) && hint+=" · Esc goes back" || hint+=" · Esc keeps $def"
  hint=${WZ_HINT:-$hint}
  [[ -n ${WZ_ESC-} ]] && cur=""
  wz_draw() {
    local -a L P out; local j lw=0 pw=0 v tag
    for (( j = 1; j <= $#vals; j++ )); do
      if (( j == sel )); then L+=("  $acc❯ ${(l:nw:)j}  $WZ_B${(r:w:)vals[j]}$WZ_R  ${descs[j]}$WZ_R")
      else
        tag=""; [[ ${vals[j]} == $cur ]] && tag="$mut  ← current$WZ_R"
        L+=("  $mut  ${(l:nw:)j}$WZ_R  ${(r:w:)vals[j]}  $mut${descs[j]}$WZ_R$tag")
      fi
      (( ${gaps[(Ie)$j]} )) && L+=("")
    done
    if [[ -n ${WZ_PREVIEW-} ]]; then
      P=("${(@f)$($WZ_PREVIEW ${vals[sel]})}")
      for v in $L; do (( (j = $(wz_vis $v)) > lw )) && lw=$j; done
      for v in $P; do (( (j = $(wz_vis $v)) > pw )) && pw=$j; done
      if (( lw + 4 + pw <= ${cols:-80} )); then
        for (( j = 1; j <= ($#L > $#P ? $#L : $#P); j++ )); do
          v=${L[j]-}; out+=("$v${(l:$(( lw - $(wz_vis $v) )):)}    ${P[j]-}")
        done
      else out=("${L[@]}" "" "${P[@]}"); fi
    else out=("${L[@]}"); fi
    (( up )) && print -rn -- $'\r\e['"${up}A" >&2
    for v in "${out[@]}"; do print -r -- $'\r\e[K'"$v" >&2; done
    print -rn -- $'\r\e[K\n\e[K'"  $mut$hint$WZ_R"$'\e[J' >&2
    up=$(( $#out + 1 ))
  }
  local esc=0
  print -n $'\e[?25l' >&2
  wz_draw
  while :; do
    if [[ -n ${WZ_IDLE-} ]]; then read -s -t 0.12 -k 1 key </dev/tty || { $WZ_IDLE >&2; continue }
    else read -s -k 1 key </dev/tty || break; fi
    case $key in
      $'\n'|$'\r') break ;;
      $'\e')
        local rest=""; read -s -t 0.05 -k 2 rest </dev/tty
        case $rest in
          '[D'|'OD') (( ${WZ_TABS:-0} )) && { esc=2; break } ;;
          '[C'|'OC') (( ${WZ_TABS:-0} )) && { esc=3; break } ;;
          '[A'|'OA') (( sel = sel > 1 ? sel - 1 : $#vals )) ;;
          '[B'|'OB') (( sel = sel < $#vals ? sel + 1 : 1 )) ;;
          '') sel=${vals[(Ie)${WZ_ESC:-$def}]}; (( sel )) || sel=1; esc=1; break ;;   # Esc on its own
        esac ;;
      k|K) (( sel = sel > 1 ? sel - 1 : $#vals )) ;;
      j|J) (( sel = sel < $#vals ? sel + 1 : 1 )) ;;
      q|Q) sel=${vals[(Ie)${WZ_ESC:-$def}]}; (( sel )) || sel=1; esc=1; break ;;
      [0-9]) num+=$key; (( num > $#vals || num == 0 )) && num=$key
             (( num >= 1 && num <= $#vals )) && sel=$num ;;
    esac
    [[ $key == [0-9] ]] || num=""
    wz_draw
  done
  print -n $'\e[?25h\n' >&2
  print -r -- ${vals[sel]}
  return esc
}

# wz_input <question> <starting text> → the edited text; Esc cancels (status 1)
wz_input() {
  local buf=$2 key rest
  print -r -- $'\n'"  $WZ_B$1$WZ_R  $(hexfg ${T[muted]})Enter saves · Esc cancels$WZ_R" >&2
  print -n $'\e[?25h' >&2
  while :; do
    print -rn -- $'\r\e[K'"  $(hexfg ${T[accent]})›$WZ_R $buf" >&2
    read -s -k 1 key </dev/tty || return 1
    case $key in
      $'\n'|$'\r') print >&2; print -r -- $buf; return 0 ;;
      $'\e') rest=""; read -s -t 0.05 -k 2 rest </dev/tty
             [[ -z $rest ]] && { print >&2; return 1 }
             [[ $rest == '['[0-9] ]] && read -s -t 0.05 -k 1 rest </dev/tty ;;   # rest of a longer key code
      $'\x7f'|$'\b') buf=${buf[1,-2]} ;;
      $'\x15') buf="" ;;                                                   # Ctrl+U
      *) [[ $key == [[:print:]] ]] && buf+=$key ;;
    esac
  done
}

wz_apply() {
  print -rn -- "  $(hexfg ${T[muted]})applying…$WZ_R"
  apply_all >/dev/null
  print -r -- $'\r\e[K'"  $(hexfg ${T[a2]})✓$WZ_R applied"
}

# wz_set <jq path> <value> → applies and succeeds if it changed, fails if it was already set
wz_set() {
  [[ $(cfg $1) == $2 ]] && return 1
  if [[ $2 == (<->|<->.<->|.<->|true|false) ]]; then cfg_set $1 $2; else cfg_set $1 "$(jstr $2)"; fi
  wz_apply
}

wz_welcome() {
  load_theme $(cfg .theme)
  wz_cls
  wz_banner
  print -r -- $'\n'"  Six quick steps: $WZ_B""theme, background, companion, layout, prompt, font$WZ_R."
  print -r -- "  Each one is applied as you pick it, so you see it straight away."
  if [[ $(cfg .configured) == true ]]; then
    print -r -- "  Each screen starts on what you have now; Enter keeps it."
  else
    print -r -- "  First frok installs its toolkit: CLI tools, starship and a Nerd Font."
  fi
  print -rn -- $'\n'"  $(hexfg ${T[muted]})press Enter to start$WZ_R  $(hexfg ${T[accent]})›$WZ_R "
  read -r </dev/tty
  print
}

wz_ready() {
  FROK_INDENT="  "
  wz_cls
  print -r -- $'\n'"  $WZ_B$(hexfg ${T[a2]})frok$WZ_R  $(hexfg ${T[muted]})getting ready$WZ_R"
  print -r -- "  $(hexfg ${T[border]})${(l:46::─:)}$WZ_R"
  print -r -- $'\n'"  $(hexfg ${T[muted]})Installing the toolkit. The first time takes a minute or two.$WZ_R"$'\n'
}

# ── previews ──────────────────────────────────────────────────────────
# wz_box <width> <line…> — lines on the theme's background, padded to one width
wz_box() {
  local W=$1 l b=$(hexfg ${T[muted]}); shift
  print -r -- "$b╭${(l:W::─:)}╮$WZ_R"
  for l; do print -r -- "$b│$(hexbg ${T[bg]})$(hexfg ${T[fg]}) $l$(hexbg ${T[bg]})${(l:$(( W - 1 - $(wz_vis $l) )):)}$WZ_R$b│$WZ_R"; done
  print -r -- "$b╰${(l:W::─:)}╯$WZ_R"
}

wz_pv_theme() {   # a small terminal session in the highlighted theme
  load_theme $1
  local f=$(hexfg ${T[fg]}) m=$(hexfg ${T[muted]}) B=$WZ_B R=$'\e[22m'
  local -a c; local i; for i in {0..7}; do c[i+1]=$(hexfg ${T[a$i]}); done
  wz_box 46 "" \
    "${c[5]}~/dev/frok$f on ${c[6]}$WZ_IC_GIT main ${c[2]}!2$f" \
    "${c[3]}❯$f ls" \
    "${c[5]}${B}docs/  lib/  themes/$R$f  README.md  ${c[3]}install.sh$f" \
    "${c[3]}❯$f git diff --stat" \
    " lib/wizard.zsh | 14 ${c[3]}+++++++++$f${c[2]}-----$f" \
    "${c[3]}❯$f echo \"\$TERM\"  ${m}# a comment$f" \
    "xterm-256color" \
    "${c[3]}❯$f ▏" "" \
    "$(swatch)  ${m}${T[name]}"
}

wz_pv_bg() {   # wz_pv_bg <rain|none|image|file> [opacity]
  local kind=$1 op=${2:-$(cfg .background_opacity)} y x line ch; local -a box
  [[ $kind == (rain|none|image) ]] || kind=image
  local col=$(hexfg $(mix ${T[a6]} ${T[bg]} $(( int(op * 100) )))) f=$(hexfg ${T[fg]})
  local -a text=("" "${f}❯ git status" "${f}On branch main" "${f}nothing to commit" "" "" "" "")
  for (( y = 1; y <= 8; y++ )); do
    line=""
    for (( x = 1; x <= 44; x++ )); do
      if (( x <= ${#${text[y]//$'\e'\[[0-9;]#m/}} + 1 && y >= 2 && y <= 4 )); then continue; fi
      case $kind in
        rain)  (( (x * 7 + y * 13 + x * y) % 11 == 0 )) && ch="╎" || ch=" " ;;
        image) (( (x + y) % 3 )) && ch="░" || ch="▒" ;;
        none)  ch=" " ;;
      esac
      line+=$ch
    done
    if (( y >= 2 && y <= 4 )); then box+=("${text[y]} $col${line}"); else box+=("$col$line"); fi
  done
  wz_box 46 "${box[@]}"
  print -r -- ""
  case $kind in
    rain)  print -r -- "  $(hexfg ${T[muted]})rain at $op, recoloured for ${T[name]}$WZ_R" ;;
    image) print -r -- "  $(hexfg ${T[muted]})your picture at $op$WZ_R" ;;
    none)  print -r -- "  $(hexfg ${T[muted]})just the theme's background$WZ_R" ;;
  esac
}
wz_pv_strength() { wz_pv_bg $(cfg .background) $1; }

wz_pv_companion() {
  local m=$(hexfg ${T[muted]}) f=$(hexfg ${T[fg]})
  if [[ $1 == none ]]; then
    print -rl -- "" "  ${m}No companion: layouts put a shell where it would be.$WZ_R"; return
  fi
  print -rl -- "$(hexfg ${T[a2]})$(pet_art $1)$WZ_R" ""
  print -r -- "$(hexfg ${T[a3]})●$WZ_R ${f}api$m · ${f}Fix the token refresh race$WZ_R"
  print -r -- "  $(hexfg ${T[a3]})needs you$m · needs permission: npm run migrate · 1m$WZ_R"
  print -r -- "$(hexfg ${T[a6]})●$WZ_R ${f}frok$m · ${f}Show a title for each split$WZ_R"
  print -r -- "  $(hexfg ${T[a6]})working…$m · Edit claude-companion.sh · 8s$WZ_R"
}

# wz_pane_label <run> → a short name for a pane in a diagram
wz_pane_label() {
  case $1 in
    companion) print frok ;;  shell) print shell ;;
    agent) local a=$(cfg .agent); print -r -- ${${a%% *}:t} ;;
    *) print -r -- ${${1%% *}:t} ;;
  esac
}

# wz_diagram <layout> <width> <height> [pane to highlight] [label for it]
# Draws the layout from its real splits: each pane takes its share of the one it split.
wz_diagram() {
  local lay=$1 W=$2 H=$3 hi=${4:-0} hl=${5-} i p x y m ch row lab lx ly own cut n
  load_layout $lay
  local -a X0 X1 Y0 Y1 labs
  X0[1]=0; X1[1]=$(( W - 1 )); Y0[1]=0; Y1[1]=$(( H - 1 ))
  for (( i = 2; i <= $#L_id; i++ )); do
    p=${L_id[(ie)${L_split[i]}]}
    X0[i]=${X0[p]}; X1[i]=${X1[p]}; Y0[i]=${Y0[p]}; Y1[i]=${Y1[p]}
    # the new pane's share, rounded, but leaving both panes at least one row/column inside
    if [[ ${L_dir[i]} == down ]]; then
      (( n = int((Y1[p] - Y0[p]) * L_size[i] + 0.5), n = n < 2 ? 2 : n, n = n > Y1[p] - Y0[p] - 2 ? Y1[p] - Y0[p] - 2 : n ))
      cut=$(( Y1[p] - n )); Y0[i]=$cut; Y1[p]=$cut
    else
      (( n = int((X1[p] - X0[p]) * L_size[i] + 0.5), n = n < 2 ? 2 : n, n = n > X1[p] - X0[p] - 2 ? X1[p] - X0[p] - 2 : n ))
      cut=$(( X1[p] - n )); X0[i]=$cut; X1[p]=$cut
    fi
  done
  typeset -A M; local -a bc=(' ' '│' '│' '│' '─' '┘' '┐' '┤' '─' '└' '┌' '├' '─' '┴' '┬' '┼')
  for (( i = 1; i <= $#L_id; i++ )); do
    for (( x = X0[i]; x < X1[i]; x++ )); do
      for y in ${Y0[i]} ${Y1[i]}; do (( M[$y,$x] |= 8, M[$y,$((x + 1))] |= 4 )); done
    done
    for (( y = Y0[i]; y < Y1[i]; y++ )); do
      for x in ${X0[i]} ${X1[i]}; do (( M[$y,$x] |= 2, M[$((y + 1)),$x] |= 1 )); done
    done
    labs[i]=$(wz_pane_label ${L_run[i]})
  done
  (( hi > 0 )) && [[ -n $hl ]] && labs[hi]=$hl
  local bcol=$(hexfg ${T[muted]}) hbg=$(hexbg $(mix ${T[accent]} ${T[bg]} 28)) f=$(hexfg ${T[fg]}) a=$(hexfg ${T[accent]})
  for (( y = 0; y < H; y++ )); do
    row="  "
    for (( x = 0; x < W; x++ )); do
      m=${M[$y,$x]:-0}
      if (( m )); then row+="$WZ_R$bcol${bc[m + 1]}"; continue; fi
      own=0
      for (( i = 1; i <= $#L_id; i++ )); do
        (( x > X0[i] && x < X1[i] && y > Y0[i] && y < Y1[i] )) && { own=$i; break }
      done
      (( own )) || { row+="$WZ_R "; continue }
      lab=${labs[own]}; ly=$(( (Y0[own] + Y1[own]) / 2 ))
      (( (X1[own] - X0[own] - 1) < $#lab )) && lab=${lab[1,$(( X1[own] - X0[own] - 1 ))]}
      lx=$(( X0[own] + 1 + (X1[own] - X0[own] - 1 - $#lab) / 2 ))
      ch=" "; (( y == ly && x >= lx && x < lx + $#lab )) && ch=${lab[x - lx + 1]}
      if (( own == hi )); then row+="$WZ_R$hbg$a$WZ_B$ch"; else row+="$WZ_R$f$ch"; fi
    done
    print -r -- "$row$WZ_R"
  done
}

wz_pv_layout() {
  wz_diagram $1 34 13
  print -r -- ""
  local l; for l in "${(@f)$(jq -r .about $(layout_file $1) | fold -s -w 36)}"; do print -r -- "  $(hexfg ${T[muted]})$l$WZ_R"; done
}

wz_pv_auto() {
  if [[ $1 == yes ]]; then
    print -rl -- "  $(hexfg ${T[muted]})a new window opens like this:$WZ_R" ""; wz_diagram $(cfg .layout) 34 13
  else
    print -rl -- "  $(hexfg ${T[muted]})a new window opens as one shell:$WZ_R" ""; wz_diagram single 34 13 1 shell
  fi
}

# ── setting screens ───────────────────────────────────────────────────
wz_theme() {
  local th c; local -a opts
  for th in $(theme_names); do load_theme $th; opts+=($th ${T[name]}); done
  load_theme $(cfg .theme)
  wz_header 1 Theme "Colours for the terminal, the prompt and the companion. Enter applies it to this window."
  c=$(WZ_PREVIEW=wz_pv_theme wz_choose $(cfg .theme) "${opts[@]}") || return 0
  wz_set .theme $c && wz_theme
}

wz_background() { wz_tabs "Background|Strength" wz_bg_kind wz_bg_strength; }

wz_bg_kind() {
  wz_header 2 Background "Sits behind your text. Rain is animated and takes the theme's colours."
  local c rc now=$(cfg .background); [[ $now == (rain|none) ]] || now=image
  c=$(WZ_TABS=1 WZ_PREVIEW=wz_pv_bg wz_choose $now \
      rain "animated, in the theme's colours" none "plain" image "your own picture or gif"); rc=$?
  (( rc )) && return rc
  if [[ $c == image ]]; then
    local cur=$(cfg .background); [[ $cur == (rain|none) ]] && cur=""
    c=$(wz_input "Path to the picture" ${cur/#$HOME/~}) || return 4
    [[ -f $(expand_home $c) ]] || { print -r -- "  $(hexfg ${T[a1]})no file at $c$WZ_R"; sleep 1.2; return 4 }
    c=${$(expand_home $c):A}
  fi
  wz_set .background $c; return 0
}

wz_bg_strength() {
  [[ $(cfg .background) == none ]] && return 4
  wz_header 2 Background "How strong should it be? Lower keeps text easier to read."
  local c rc; c=$(WZ_TABS=1 WZ_PREVIEW=wz_pv_strength wz_choose $(cfg .background_opacity) \
      0.1 subtle 0.2 balanced 0.35 bold 0.5 loud); rc=$?
  (( rc )) && return rc
  wz_set .background_opacity $c; return 0
}

wz_companion() {
  wz_header 3 Companion "A pane that shows your Claude Code sessions: who's busy, who's waiting on you."
  local -a opts=() n
  for n in $(companion_names); do opts+=($n "$(sed -n '1s/^# [a-z]* — //p' $COMPANION_DIR/pets/$n.zsh)"); done
  local c; c=$(WZ_PREVIEW=wz_pv_companion wz_choose $(cfg .companion) "${opts[@]}" none "no companion") || return 0
  wz_set .companion $c || true
}

wz_layout() { wz_tabs "Layout|Every window|Panes" wz_layout_pick wz_layout_auto wz_layout_panes; }

wz_layout_pick() {
  local -a opts=() n; local c rc
  for n in $(layout_names); do opts+=($n ""); done
  wz_header 4 Layout "How a new terminal window is split."
  c=$(WZ_TABS=1 WZ_PREVIEW=wz_pv_layout wz_choose $(cfg .layout) "${opts[@]}"); rc=$?
  (( rc )) && return rc
  wz_set .layout $c; return 0
}

wz_layout_auto() {
  [[ $(cfg .layout) == single ]] && return 4
  wz_header 4 Layout "Open every new terminal window in the $(cfg .layout) layout?"
  local later="split it yourself" c rc
  wz_has_wt && later+=" (Ctrl+Shift+L)"
  c=$(WZ_TABS=1 WZ_PREVIEW=wz_pv_auto wz_choose $([[ $(cfg .layout_on_start) == true ]] && print yes || print no) \
      yes "every new window starts split" no $later); rc=$?
  (( rc )) && return rc
  wz_set .layout_on_start $([[ $c == yes ]] && print true || print false); return 0
}

# What each split of the current layout runs and where it starts.
wz_run_label() {
  case $1 in
    agent) cfg .agent ;;  companion) print -r -- "frok, watching your sessions" ;;
    shell) print -r -- "a shell" ;;  *) print -r -- $1 ;;
  esac
}

wz_pv_panes() {
  local l=$(cfg .layout) i
  load_layout $l
  i=${L_name[(Ie)$1]}
  wz_diagram $l 34 13 $i
  print -r -- ""
  if (( i )); then
    print -r -- "  $(hexfg ${T[muted]})runs      $WZ_R$(wz_run_label ${L_run[i]})"
    [[ ${L_run[i]} == companion ]] || print -r -- "  $(hexfg ${T[muted]})starts in $WZ_R${L_cwd[i]}"
  elif [[ $1 == "default folder" ]]; then
    print -r -- "  $(hexfg ${T[muted]})splits start in $WZ_R$(cfg .workdir)$(hexfg ${T[muted]}) unless set$WZ_R"
  fi
}

wz_layout_panes() {
  local l=$(cfg .layout) i c rc d
  load_layout $l
  local -a names=("${L_name[@]}") runs=("${L_run[@]}") cwds=("${L_cwd[@]}")
  wz_header 4 Layout "What each split of the $l layout runs, and where it starts. Pick one to change it."
  local -a opts=("default folder" "$(cfg .workdir)" -)
  for (( i = 1; i <= $#names; i++ )); do opts+=("${names[i]}" "$(wz_pane_label ${runs[i]})"); done
  opts+=(- done "")
  local esc="Esc moves on"; (( ${WZ_SOLO:-0} )) && esc="Esc goes back"
  c=$(WZ_TABS=1 WZ_ESC=done WZ_PREVIEW=wz_pv_panes WZ_HINT="↑↓ to move, Enter to change it · ←→ switch tabs · $esc" \
      wz_choose done "${opts[@]}"); rc=$?
  (( rc )) && return rc
  case $c in
    done) return 0 ;;
    "default folder") wz_folder_default ;;
    *) wz_pane_edit $l ${names[(Ie)$c]} ;;
  esac
  wz_layout_panes; return
}

# wz_check_dir <path as typed> → the same path with ~ for home, or fails if it isn't a folder
wz_check_dir() {
  local p=$(expand_home $1)
  [[ -d $p ]] || { print -r -- "  $(hexfg ${T[a1]})no folder at $1$WZ_R" >&2; sleep 1.2; return 1 }
  p=${p:A}; [[ $p == $HOME(/*|) ]] && p="~${p#$HOME}"
  print -r -- $p
}

wz_folder_default() {
  wz_header 4 Layout "Where splits start unless one says otherwise."
  local d; d=$(wz_input "Default folder" $(cfg .workdir)) || return 0
  d=$(wz_check_dir $d) || return 0
  [[ $d == $(cfg .workdir) ]] || { cfg_set .workdir "$(jstr $d)"; wz_apply }
}

wz_pv_paneedit() {   # the edited split, showing what it would run
  local lab
  case $1 in companion) lab=frok ;; shell) lab=shell ;; *) lab=$(wz_pane_label ${WZ_PANE_RUN:-agent}) ;; esac
  wz_diagram $(cfg .layout) 34 13 $WZ_PANE $lab
}

wz_pane_edit() {   # wz_pane_edit <layout> <pane number>
  local l=$1 i=$2 c cur d
  load_layout $l
  local name=${L_name[i]} run=${L_run[i]} key=".panes[\"$1\"][\"${L_id[i]}\"]"
  local now=$run; [[ $run == agent ]] && now=$(cfg .agent)
  wz_header 4 Layout "The $name split: what should it run?"
  cur=command; [[ $run == (shell|companion) ]] && cur=$run
  c=$(WZ_PANE=$i WZ_PANE_RUN=${${run:#(shell|companion)}:-agent} WZ_PREVIEW=wz_pv_paneedit \
      wz_choose $cur companion "frok, watching your sessions" shell "a plain shell" \
      command "${${now:#(shell|companion)}:-a command you type}") || return 0
  if [[ $c == command ]]; then
    c=$(wz_input "Command for the $name split" ${${now:#(shell|companion)}:-$(cfg .agent)}) || return 0
    [[ -n $c ]] || return 0
    [[ $c == $(cfg .agent) ]] && c=agent
  fi
  cfg_set "$key.run" "$(jstr $c)"
  if [[ $c != companion ]]; then
    wz_header 4 Layout "The $name split: where should it start?"
    local fdesc="a folder you type"
    cur=default; [[ -n $(jq -r "$key.dir // empty" $FROK_CFG) ]] && { cur=folder; fdesc=${L_cwd[i]} }
    d=$(wz_choose $cur default "$(cfg .workdir), like the other splits" folder $fdesc) || d=keep
    case $d in
      folder) d=$(wz_input "Folder for the $name split" ${L_cwd[i]}) && d=$(wz_check_dir $d) && cfg_set "$key.dir" "$(jstr $d)" ;;
      default) jq "del($key.dir)" $FROK_CFG >| $FROK_CFG.tmp && mv -f $FROK_CFG.tmp $FROK_CFG ;;
    esac
  fi
  wz_apply
}

wz_pv_prompt() {
  local -a c; local i; for i in {0..7}; do c[i+1]=$(hexfg ${T[a$i]}); done
  local f=$(hexfg ${T[fg]})
  if [[ $1 == starship ]]; then
    wz_box 40 "" "${c[5]}~/dev/frok$f on ${c[6]}$WZ_IC_GIT main ${c[2]}!2$f" "${c[3]}❯$f git status" "" \
      "${c[5]}~/dev/frok$f on ${c[6]}$WZ_IC_GIT main ${c[2]}!2 ${c[4]}took 3s$f" "${c[3]}❯$f ▏" ""
  else
    wz_box 40 "" "$USER@${HOST:-$(hostname)}:~/dev/frok\$ git status" "" "$USER@${HOST:-$(hostname)}:~/dev/frok\$ ▏" ""
  fi
}

wz_prompt() {
  wz_header 5 Prompt "The line you type after. Starship shows the folder, git branch and status, themed."
  local c; c=$(WZ_PREVIEW=wz_pv_prompt wz_choose $(cfg .prompt) starship "folder, git, status in colour" none "keep your current prompt") || return 0
  wz_set .prompt $c || true
}

wz_font() { wz_tabs "Font|Size" wz_font_family wz_font_size; }

wz_pv_font() {
  local m=$(hexfg ${T[muted]})
  wz_box 34 "" "The quick brown fox jumps" "0O 1lI 5S 8B  {} [] ()" "-> => != === <= >= |>" \
    "$(hexfg ${T[a4]})$WZ_IC_DIR $(hexfg ${T[a5]})$WZ_IC_GIT $(hexfg ${T[a2]})$WZ_IC_TERM $(hexfg ${T[a3]})$WZ_IC_NODE $(hexfg ${T[a6]})$WZ_IC_GH  $(hexfg ${T[fg]})icons the prompt uses" ""
  print -rl -- "" "  ${m}Drawn in your current font; $1$WZ_R" "  ${m}shows after you restart the terminal.$WZ_R"
}

wz_font_family() {
  local -a opts; local cur=$(cfg .font.family) c rc
  opts=(CaskaydiaCove "Cascadia Code, ligatures" JetBrainsMono "tall, easy to read"
        FiraCode "ligatures" Hack "plain, no ligatures" MesloLGS "Menlo-like")
  (( ${opts[(Ie)${cur% Nerd Font}]} )) || opts+=("$cur" "(yours)")
  local note="Nerd Fonts carry the icons the prompt and tools use; frok downloads the one you pick."
  wz_header 6 Font $note
  c=$(WZ_TABS=1 WZ_PREVIEW=wz_pv_font wz_choose "${cur% Nerd Font}" "${opts[@]}"); rc=$?
  (( rc )) && return rc
  [[ -n ${NERD_ZIP[$c Nerd Font]} ]] && c+=" Nerd Font"
  wz_set .font.family $c; return 0
}

wz_font_size() {
  wz_header 6 Font "Font size."
  local c rc; c=$(WZ_TABS=1 wz_choose $(cfg .font.size) 10 small 11 "" 12 "" 13 "" 14 "roomy, good on Retina" 16 large); rc=$?
  (( rc )) && return rc
  wz_set .font.size $c; return 0
}

wz_done() {
  local m=$(hexfg ${T[muted]}) tl=$(cfg .layout)
  local bg=$(cfg .background); [[ $bg == none ]] || bg+=" at $(cfg .background_opacity)"
  [[ $(cfg .layout_on_start) == true && $tl != single ]] && tl+=", in every new window"
  wz_cls
  wz_banner
  print -r -- $'\n'"  $(hexfg ${T[a2]})✓$WZ_R $WZ_B""all set$WZ_R"$'\n'
  print -r -- "  ${m}theme$WZ_R       $(cfg .theme)  $(swatch)"
  print -r -- "  ${m}background$WZ_R  $bg"
  print -r -- "  ${m}companion$WZ_R   $(cfg .companion)"
  print -r -- "  ${m}layout$WZ_R      $tl"
  print -r -- "  ${m}prompt$WZ_R      $(cfg .prompt)"
  print -r -- "  ${m}font$WZ_R        $(cfg .font.family), $(cfg .font.size)"
  print -r -- $'\n'"  Open a new terminal window to see it all. Run $WZ_B""frok$WZ_R any time to change things."
}

wizard() {
  local FROK_INDENT="  "
  load_theme $(cfg .theme)
  wz_apply
  wz_theme
  wz_background
  wz_companion
  wz_layout
  wz_prompt
  wz_font
  wz_done
}

# The menu (`frok menu`, or `,` in the companion): every setting with its current
# value, and the things you can do. A setting opens its one wizard screen.
wz_back() { print -rn -- $'\n'"  $(hexfg ${T[muted]})press Enter to go back$WZ_R  $(hexfg ${T[accent]})›$WZ_R "; read -r </dev/tty; }

# wz_after <status> — after a check: on success, back to the menu in 3s (any key: now);
# on problems, wait for Enter so they can be read
wz_after() {
  if (( $1 )); then wz_back; return; fi
  local n key
  for n in 3 2 1; do
    print -rn -- $'\r\e[K'"  $(hexfg ${T[muted]})back to the menu in $n… (any key: now)$WZ_R" 
    read -s -t 1 -k 1 key </dev/tty && break
  done
  print
}

wz_menu() {
  local c bg tl; local -a opts
  local WZ_SOLO=1 FROK_INDENT="  "
  while :; do
    load_theme $(cfg .theme)
    bg=$(cfg .background); [[ $bg == none ]] || bg+=" at $(cfg .background_opacity)"
    tl=$(cfg .layout); [[ $(cfg .layout_on_start) == true && $tl != single ]] && tl+=", in every new window"
    opts=(theme "$(cfg .theme)  $(swatch)" background $bg companion "$(cfg .companion)" layout $tl
          prompt "$(cfg .prompt)" font "$(cfg .font.family), $(cfg .font.size)")
    wz_has_wt && opts+=("open layout" "split a new window into $(cfg .layout) now")
    opts+=("full setup" "all six steps in a row" "health check" "is everything installed and hooked up?"
           update "pull the latest frok and re-apply")
    opts+=(- quit "")
    wz_cls
    wz_banner "what would you like to change?"
    print
    local idle=""; local sz=$(stty size </dev/tty 2>/dev/null)
    (( ${sz% *} >= 28 && ${sz#* } >= 80 )) && idle=wz_frog_idle   # needs the banner on screen, unscrolled
    c=$(WZ_IDLE=$idle WZ_ESC=quit WZ_HINT="↑↓ to move, Enter to pick · q quits" wz_choose theme "${opts[@]}")
    case $c in
      theme) wz_theme ;;  background) wz_background ;;  companion) wz_companion ;;
      layout) wz_layout ;;  prompt) wz_prompt ;;  font) wz_font ;;
      "open layout") $FROK_HOME/bin/frok layout open; sleep 1 ;;
      "full setup") WZ_SOLO=0 wizard; wz_back ;;
      "health check") wz_header 0 "Health check" "Is everything installed and hooked up?"; doctor; wz_after $? ;;
      update) wz_header 0 Update "Pulling the latest frok and re-applying it."; FROK_INDENT="  " $FROK_HOME/bin/frok update; wz_after $? ;;
      quit) wz_cls; return ;;
    esac
  done
}

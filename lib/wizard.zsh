# wizard.zsh — the step-by-step setup in the terminal: a banner, then one
# screen per setting. Each pick is applied straight away so the terminal shows
# it; Enter keeps the highlighted choice and moves on.

WZ_STEPS=6
WZ_R=$'\e[0m' WZ_B=$'\e[1m'

hexfg() { local c=${1#\#}; print -rn -- $'\e[38;2;'"$((0x${c:0:2}));$((0x${c:2:2}));$((0x${c:4:2}))m"; }

wz_cls() { [[ -t 1 ]] && print -n $'\e[2J\e[H'; }

wz_banner() {
  local -a logo=(
    ''
    '██████████  ████████      ██████    ██      ██'
    '██          ██      ██  ██      ██  ██    ██'
    '████████    ████████    ██      ██  ██████'
    '██          ██    ██    ██      ██  ██    ██'
    '██          ██      ██    ██████    ██      ██'
  )
  local -a frog=("${(@f)$(<$FROK_HOME/companions/frog/frog.txt)}")
  local i
  (( ${COLUMNS:-$(tput cols 2>/dev/null || print 80)} < 80 )) && frog=('' '' '' '' '' '')   # the logo alone fits
  print
  for (( i = 1; i <= $#frog; i++ )); do
    print -r -- "  $(hexfg $(mix ${T[accent]} ${T[accent2]} $(( 100 - 100 * (i - 1) / ($#frog - 1) ))))${(r:49:)logo[i]}$(hexfg ${T[a2]})${frog[i]:5}$WZ_R"
  done
  print -r -- $'\n'"  $(hexfg ${T[muted]})your terminal, set up one step at a time$WZ_R"
}

wz_header() {   # wz_header <step> <title> <what it's about>
  local i dots=""
  for (( i = 1; i <= WZ_STEPS; i++ )); do
    (( i <= $1 )) && dots+="$(hexfg ${T[accent]})●" || dots+="$(hexfg ${T[border]})○"
  done
  wz_cls
  print -r -- $'\n'"  $WZ_B$(hexfg ${T[a2]})frok$WZ_R  $dots$WZ_R  $(hexfg ${T[muted]})step $1 of $WZ_STEPS$WZ_R"
  print -r -- "  $(hexfg ${T[border]})${(l:46::─:)}$WZ_R"
  print -r -- $'\n'"  $WZ_B$2$WZ_R"
  print -r -- "  $(hexfg ${T[muted]})$3$WZ_R"$'\n'
}

# wz_choose <default> <value> <description> [<value> <description>…] → the chosen value
# Accepts a number, a value, or Enter for the default.
wz_choose() {
  local def=$1; shift
  local -a vals descs; while (( $# )); do vals+=($1); descs+=("$2"); shift 2; done
  local i w=0 ans line=""
  for i in $vals; do (( $#i > w )) && w=$#i; done
  if (( ${WZ_COMPACT:-0} )); then   # one line, for screens that already show the options
    for (( i = 1; i <= $#vals; i++ )); do
      [[ ${vals[i]} == $def ]] && line+="$(hexfg ${T[accent]})❯ $i $WZ_B${vals[i]}$WZ_R   " || line+="$(hexfg ${T[muted]})  $i$WZ_R ${vals[i]}   "
    done
    print -r -- "  $line" >&2
  fi
  for (( i = 1; i <= $#vals && ! ${WZ_COMPACT:-0}; i++ )); do
    if [[ ${vals[i]} == $def ]]; then
      print -r -- "  $(hexfg ${T[accent]})❯ $i  $WZ_B${(r:w:)vals[i]}$WZ_R  ${descs[i]}$WZ_R" >&2
    else
      print -r -- "  $(hexfg ${T[muted]})  $i$WZ_R  ${(r:w:)vals[i]}  $(hexfg ${T[muted]})${descs[i]}$WZ_R" >&2
    fi
  done
  print -rn -- $'\n'"  $(hexfg ${T[muted]})Enter keeps ${def}, or type a number$WZ_R  $(hexfg ${T[accent]})›$WZ_R " >&2
  read -r ans </dev/tty
  if [[ -z $ans ]]; then print -r -- $def
  elif [[ $ans == <-> ]] && (( ans >= 1 && ans <= $#vals )); then print -r -- ${vals[ans]}
  elif (( ${vals[(Ie)$ans]} )); then print -r -- $ans
  else print -r -- $def; fi
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
  print -r -- "  First frok installs its toolkit: CLI tools, starship and a Nerd Font."
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

wz_theme() {
  local th c; local -a opts
  for th in $(theme_names); do load_theme $th; opts+=($th "$(swatch)  ${T[name]}"); done
  load_theme $(cfg .theme)
  wz_header 1 Theme "Colours for the terminal, the prompt and the companion. Try a few: each recolours this window."
  c=$(wz_choose $(cfg .theme) "${opts[@]}")
  wz_set .theme $c && wz_theme
}

wz_background() {
  wz_header 2 Background "Sits behind your text. Rain is animated and takes the theme's colours."
  local c=$(wz_choose $(cfg .background) \
      rain "animated rain in the theme's colours" none "plain background" image "your own picture or gif")
  if [[ $c == image ]]; then
    local p; print -rn -- "  path to the image › "; read -r p </dev/tty; p=$(expand_home $p)
    [[ -f $p ]] && c=${p:A} || { print "  no file there"; sleep 1; c=$(cfg .background) }
  fi
  wz_set .background $c && { wz_background; return }
  [[ $c == none ]] || wz_opacity
}

wz_opacity() {
  wz_header 2 Background "How strong should it be? Lower keeps text easier to read."
  wz_set .background_opacity $(wz_choose $(cfg .background_opacity) 0.1 subtle 0.2 balanced 0.35 bold 0.5 loud) && wz_opacity
}

wz_companion() {
  wz_header 3 Companion "A pet pane that shows your Claude Code sessions: who's busy, who's waiting on you."
  print -r -- "$(hexfg ${T[a2]})${(F)${(@f)$(<$FROK_HOME/companions/frog/frog.txt)}}$WZ_R"$'\n'
  local -a opts=() n
  for n in $(companion_names); do opts+=($n "watches your sessions, tells the odd fact"); done
  wz_set .companion $(wz_choose $(cfg .companion) "${opts[@]}" none "no companion") || true
}

wz_layout() {
  local -a names=($(layout_names)) row lines
  local cols=$(( (${COLUMNS:-$(tput cols 2>/dev/null || print 80)} - 2) / 29 )) i j n cur=$(cfg .layout) col
  (( cols < 1 )) && cols=1
  wz_header 4 Layout "How a new terminal window is split. Agent panes run $(cfg .agent)."
  for (( i = 1; i <= $#names; i += cols )); do
    row=(${names[i,i+cols-1]})
    lines=()
    for n in $row; do
      col=$(hexfg ${T[muted]}); [[ $n == $cur ]] && col=$(hexfg ${T[accent]})
      lines[1]+="  $col$(( ${names[(i)$n]} )) ${(r:24:)n}$WZ_R  "
      local -a d=("${(@f)$(jq -r '.diagram[]?' $(layout_file $n))}")
      for (( j = 1; j <= 9; j++ )); do lines[j+1]+="  $col${(r:25:)d[j]}$WZ_R   "; done
    done
    print -rl -- $lines ''
  done
  local -a opts=(); for n in $names; do opts+=($n ""); done
  wz_set .layout $(WZ_COMPACT=1 wz_choose $cur "${opts[@]}") && { wz_layout; return }
  [[ $cur == single ]] && return
  wz_header 4 Layout "Open every new terminal window in this layout?"
  local later="split on demand with frok layout open"
  terminals_active | grep -qx windows-terminal && later+=" or Ctrl+Shift+L"
  local on=$(wz_choose $([[ $(cfg .layout_on_start) == true ]] && print yes || print no) \
      yes "every new window starts split" no $later)
  wz_set .layout_on_start $([[ $on == yes ]] && print true || print false) || true
}

wz_prompt() {
  wz_header 5 Prompt "The line you type after. Starship shows the folder, git branch and status, themed."
  print -r -- "  $(hexfg ${T[a4]})~/dev/frok$WZ_R on $(hexfg ${T[a5]}) main$WZ_R $(hexfg ${T[a1]})!2$WZ_R"
  print -r -- "  $(hexfg ${T[a2]})❯$WZ_R git status   $(hexfg ${T[muted]})← starship$WZ_R"$'\n'
  wz_set .prompt $(wz_choose $(cfg .prompt) starship "folder, git, status in colour" none "keep your current prompt") || true
}

wz_font() {
  local -a opts; local cur=$(cfg .font.family)
  opts=(CaskaydiaCove "Cascadia Code with icons, ligatures" JetBrainsMono "tall letters, easy on the eyes"
        FiraCode "ligatures, a long-time favourite" Hack "plain and sturdy, no ligatures"
        MesloLGS "Menlo-like, feels like macOS")
  (( ${opts[(Ie)${cur% Nerd Font}]} )) || opts+=("$cur" "(yours)")
  local note="Nerd Fonts carry the icons the prompt and tools use; frok downloads the one you pick."
  [[ $OS == wsl ]] && note+=" Restart Windows Terminal afterwards to see it."
  wz_header 6 Font $note
  local c=$(wz_choose "${cur% Nerd Font}" "${opts[@]}")
  [[ -n ${NERD_ZIP[$c Nerd Font]} ]] && c+=" Nerd Font"
  wz_set .font.family $c || true
  wz_header 6 Font "Font size."
  wz_set .font.size $(wz_choose $(cfg .font.size) 10 small 11 "" 12 "" 13 "" 14 "roomy, good on Retina" 16 large) || true
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

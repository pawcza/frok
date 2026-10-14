# input.zsh — keys and clicks: tricks, pages, periods, settings, and the
# session buttons.

# click_button <x> <"fs:fe/cs:ce/pane"> — focus, or close (asks once: "sure?")
click_button() {
  local x=$1 f c pane; f=${${2}%%/*}; c=${${2#*/}%%/*}; pane=${2##*/}
  if [[ -n $f ]] && (( x >= ${f%%:*} && x <= ${f##*:} )); then focus_pane $pane; return 0; fi
  if [[ -n $c ]] && (( x >= ${c%%:*} && x <= ${c##*:} )); then
    if [[ $confirm == $pane ]]; then
      [[ ${panepid[$pane]} == <-> ]] && kill -TERM ${panepid[$pane]} 2>/dev/null   # ends Claude; the pane keeps its shell
      confirm=""
    else confirm=$pane; confirm_until=$(( tick + 15 )); fi
    return 0
  fi
  return 1
}

# handle_input — act on one key press or mouse report in $buf (read by the main loop)
handle_input() {
  if [[ $buf == $'\e[<'(#b)([0-9]##)';'([0-9]##)';'([0-9]##)M* ]]; then
    btn=$match[1]; mx=$match[2]; my=$match[3]
    if (( btn == 0 && mx >= 2 && mx <= 32 && my >= 2 && my <= 7 )); then   # poked the frog
      if [[ -z $phase ]]; then
        (( annoy++ )); last_click=$tick
        (( annoy >= 12 )) && { phase=bye; phase_t=$tick; }
      fi
    elif (( btn == 0 )) && (( (ri = my - sess_off) >= 1 )) && [[ -n ${btns[$ri]} ]] && click_button $mx "${btns[$ri]}"; then
      :                                                             # a session's focus / ✕ button
    elif (( btn == 0 )) && [[ -n $pager ]] && (( my - sess_off == ${pager%%/*} )); then
      pp=(${(s:/:)pager})                                           # ‹ prev / next ›
      (( mx >= ${pp[2]%%:*} && mx <= ${pp[2]##*:} && pg > 1 )) && (( pg-- ))
      (( mx >= ${pp[3]%%:*} && mx <= ${pp[3]##*:} && pg < npg )) && (( pg++ ))
    elif (( btn == 0 && ( stacked || mx >= 36 ) )) && (( (ri = my - sess_off) >= 1 && ri <= ${#rowpane} )) && [[ -n ${rowpane[$ri]} ]] && own_pane "${rowpane[$ri]}"; then
      focus_pane "${rowpane[$ri]}"                                  # left-click a session → jump to its pane
    elif (( btn == 0 && my == keysrow )) && [[ ${keypos[1]} == 1:* ]] && (( mx >= LW + ${${(s.:.)keypos[1]}[2]} && mx <= LW + ${${(s.:.)keypos[1]}[3]} )); then
      open_settings                                                 # the settings button
    elif (( btn == 0 && my >= tricksrow && my < tricksrow + ${#tricklines} )); then   # click a trick
      for tp in $trickpos; do
        tq=(${(s.:.)tp})
        (( my == tricksrow + tq[1] - 1 && mx >= LW + tq[2] && mx <= LW + tq[3] )) && [[ -z $phase ]] && start_trick ${trickkey[${tq[4]}]}
      done
    elif (( btn == 0 && my == statsrow )); then                     # click a period tab
      for (( k = 1; k <= 3; k++ )); do
        (( mx >= ${tabx[k]%%:*} && mx <= ${tabx[k]##*:} )) && pi=$k
      done
    fi
  elif [[ $buf == , ]]; then                                           # , → settings
    open_settings
  elif [[ $buf == p ]]; then                                           # p → next period
    (( pi = pi % 3 + 1 ))
  elif [[ $buf == '[' ]]; then (( pg > 1 )) && (( pg-- ))              # [ / ] → session pages
  elif [[ $buf == ']' ]]; then (( pg < npg )) && (( pg++ ))
  elif [[ $buf == " " ]]; then                                         # space → new useless fact
    fetch_fact
  elif [[ -n ${trickkey[$buf]} && -z $phase ]]; then                    # the pet's tricks on demand
    start_trick ${trickkey[$buf]}
  fi
}

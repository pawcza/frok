# timer — a focus timer: T starts and stops it, the pet cheers and you get a notification when it's done. Options: minutes (25), break (5).
# options: minutes break
W_LABEL[timer]=timer; W_KEYS[T]=timer

# state: "<started at> <seconds> <focus|break>", shared by every companion
w_timer_file=$WSTATE/timer
w_timer_read() { w_timer=(); [[ -r $w_timer_file ]] && w_timer=(${=$(<$w_timer_file)}); }
w_timer_key() {
  w_timer_read
  if (( ${#w_timer} )); then rm -f $w_timer_file                       # running or finished: stop
  else print -r -- "$EPOCHSECONDS $(( $(wopt timer minutes 25) * 60 )) focus" >| $w_timer_file; fi
  w_timer_read
}
w_timer_click() {
  [[ $1 == break ]] && { print -r -- "$EPOCHSECONDS $(( $(wopt timer break 5) * 60 )) break" >| $w_timer_file; w_timer_read; return; }
  w_timer_key
}
w_timer_refresh() {
  (( tick % 5 == 0 )) && w_timer_read
  (( ${#w_timer} == 3 )) || return
  if (( EPOCHSECONDS >= w_timer[1] + w_timer[2] )) && [[ ${w_timer_done-} != ${w_timer[1]} ]]; then
    w_timer_done=${w_timer[1]}
    start_ev yay 20; print -n $'\a'
    [[ ${w_timer[3]} == focus ]] && notify "frok" "Focus time's up. Take a break." || notify "frok" "Break's over."
  fi
}

w_timer_render() {
  if (( ${#w_timer} != 3 )); then
    wl=("${KB} T ${X} ${D}start a $(wopt timer minutes 25) min focus${X}"); wclick+=("1:1:3:start"); return
  fi
  local left=$(( w_timer[1] + w_timer[2] - EPOCHSECONDS )) pct
  if (( left <= 0 )); then
    if [[ ${w_timer[3]} == focus ]]; then         # "done!  [ break ] 5 min   [ T ] stop"
      local note="$(wopt timer break 5) min" x
      wl=("${G}done!${X}  ${KB} break ${X} ${D}${note}${X}   ${KB} T ${X} ${D}stop${X}")
      (( x = 8 + 7 + 1 + ${#note} + 3 ))
      wclick+=("1:8:14:break" "1:$x:$(( x + 2 )):stop")
    else wl=("${G}break's over${X}   ${KB} T ${X} ${D}clear${X}"); wclick+=("1:16:18:stop"); fi
    return
  fi
  local ss=$(( left % 60 )); (( pct = (w_timer[2] - left) * 100 / w_timer[2] ))
  wl=("${D}${w_timer[3]} ${X}$(bar $pct)  ${W}$(( left / 60 )):${(l:2::0:)ss}${X}${D} left   ${X}${KB} T ${X} ${D}stop${X}")
  wclick+=("1:1:${cw}:stop")
}

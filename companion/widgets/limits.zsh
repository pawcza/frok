# limits — your 5-hour and 7-day usage limits, from Claude Code's status line.
W_LABEL[limits]=limits

lim=()
refresh_limits() {       # the newest status that reported limits
  local f ts ctx h5 h5r d7 d7r acct; lim=()
  for f in $STATE/status/*(N.om); do
    IFS=$US read -r ts ctx h5 h5r d7 d7r acct < $f 2>/dev/null || continue
    [[ -n $h5$d7 ]] && { lim=("$h5" "$h5r" "$d7" "$d7r" "$acct"); return; }
  done
}
w_limits_refresh() { (( tick % 25 == 0 )) && refresh_limits; }

w_limits_render() {
  local row=""
  if (( ! ${#lim} )); then wl=("${D}shows after Claude's next reply (needs a Pro/Max plan)${X}"); return; fi
  [[ -n ${lim[1]} ]] && { (( EPOCHSECONDS >= ${lim[2]:-0} )) && lim[1]=0
    row+="${D}5h ${X}$(bar ${lim[1]})${D}  resets in $(dur $(( ${lim[2]:-0} - EPOCHSECONDS )))${X}"; }
  [[ -n ${lim[3]} ]] && { (( EPOCHSECONDS >= ${lim[4]:-0} )) && lim[3]=0
    row+="${row:+     }${D}7d ${X}$(bar ${lim[3]})${D}  resets $(strftime '%a %H:%M' ${lim[4]:-0})${X}"; }
  wl=("$row")
}

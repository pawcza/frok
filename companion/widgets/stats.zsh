# stats — tokens, lines changed, commits by day; p or a click switches (Claude Code only; hidden otherwise).
W_LABEL[stats]=stats; W_KEYS[p]=stats

plabel=("today" "7 days" "30 days"); pi=1; statvals=()
refresh_stats() {        # sums from stats.sh's per-day index
  statvals=()
  [[ -r $STATE/stats/days.json ]] && jq -e 'length > 0' $STATE/stats/days.json >/dev/null 2>&1 || return
  statvals=("${(@f)$(jq -r --arg t $(strftime %F $EPOCHSECONDS) --arg w $(strftime %F $(( EPOCHSECONDS - 6*86400 ))) \
      --arg m $(strftime %F $(( EPOCHSECONDS - 29*86400 ))) '
    def sum($from): [to_entries[] | select(.key >= $from) | .value]
      | [ (map(.tok // 0) | add // 0), (map(.add // 0) | add // 0), (map(.del // 0) | add // 0), (map(.commits // 0) | add // 0) ]
      | map(tostring) | join("\t");
    sum($t), sum($w), sum($m)' $STATE/stats/days.json 2>/dev/null)}")
}
run_stats() { [[ -z ${FROK_DEMO-} && -x $HERE/stats.sh ]] && { FROK_STATE=${STATE:h} $HERE/stats.sh >/dev/null 2>&1 &! }; }

w_stats_refresh() {
  (( tick % 300 == 0 )) && run_stats            # index new transcript bytes once a minute
  (( tick % 25 == 0 )) && refresh_stats
}
w_stats_key() { (( pi = pi % 3 + 1 )); }
w_stats_click() { pi=$1; }

w_stats_render() {
  local tabs="" x=1 k nums numw tabw stok sadd sdel scom
  (( ${#statvals} == 3 )) || claude_in_use || return 0
  for (( k = 1; k <= 3; k++ )); do
    wclick+=("1:$x:$(( x + ${#plabel[k]} + 1 )):$k"); (( x += ${#plabel[k]} + 3 ))
    (( k == pi )) && tabs+="${KB}${ACC}"$'\e[1m'" ${plabel[k]} ${X} " || tabs+="${D} ${plabel[k]} ${X} "
  done
  (( tabw = x - 1 ))
  if (( ${#statvals} == 3 )); then
    IFS=$TAB read -r stok sadd sdel scom <<< "${statvals[pi]}"
    nums="${W}$(human $stok)${X}${D} tokens${X}   ${G}+$(human $sadd)${X} ${R}−$(human $sdel)${X}${D} lines${X}   ${W}${scom}${X}${D} commit$( (( scom == 1 )) || print -n s)${X}"
    numw=$(( ${#$(human $stok)} + 7 + 3 + ${#$(human $sadd)} + ${#$(human $sdel)} + 9 + 3 + ${#scom} + 8 ))
  else nums="${D}counting… (first pass reads all your transcripts)${X}"; numw=49; fi
  if (( tabw + 2 + numw <= cw )); then wl=("$tabs  $nums"); else wl=("$tabs" "$nums"); fi
}

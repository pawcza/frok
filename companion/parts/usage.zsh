# usage.zsh — usage stats (stats.sh indexes the transcripts) and the 5-hour /
# 7-day limits (from the status line).

# ── stats: tokens, lines, commits per day (stats.sh indexes the transcripts) ──
periods=(today week month); plabel=("today" "7 days" "30 days"); pi=1; statvals=()
refresh_stats() {
  [[ -r $STATE/stats/days.json ]] || { statvals=(); return }
  statvals=("${(@f)$(jq -r --arg t $(strftime %F $EPOCHSECONDS) --arg w $(strftime %F $(( EPOCHSECONDS - 6*86400 ))) \
      --arg m $(strftime %F $(( EPOCHSECONDS - 29*86400 ))) '
    def sum($from): [to_entries[] | select(.key >= $from) | .value]
      | [ (map(.tok // 0) | add // 0), (map(.add // 0) | add // 0), (map(.del // 0) | add // 0), (map(.commits // 0) | add // 0) ]
      | map(tostring) | join("\t");
    sum($t), sum($w), sum($m)' $STATE/stats/days.json 2>/dev/null)}")
}
run_stats() { [[ -z ${FROK_DEMO-} && -x $HERE/stats.sh ]] && { FROK_STATE=${STATE:h} $HERE/stats.sh >/dev/null 2>&1 &! }; }

# ── usage limits: the newest status Claude Code's status line reported ──
lim=()
refresh_limits() {
  local f ts ctx h5 h5r d7 d7r acct; lim=()
  for f in $STATE/status/*(N.om); do
    IFS=$US read -r ts ctx h5 h5r d7 d7r acct < $f 2>/dev/null || continue
    [[ -n $h5$d7 ]] && { lim=("$h5" "$h5r" "$d7" "$d7r" "$acct"); return; }
  done
}

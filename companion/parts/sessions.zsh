# sessions.zsh — the session list: hook records, cross-checked against each
# transcript and the status line.

# ── transcripts: context used, and whether the last turn has ended ─────
# Re-read only when the file changes. Hooks can arrive late or out of order
# (a background subagent finishing after the turn), the transcript can't.
typeset -A tcache
transcript_info() {   # transcript_info <path> → tctx (% of the context window), tended (1 = turn over)
  local tp=$1 mt model used win; local -a m; tctx=""; tended=""
  [[ -n $tp && -r $tp ]] || return
  zstat -A m +mtime -- $tp 2>/dev/null; mt=${m[1]}
  if [[ ${tcache[$tp]%%$US*} != $mt ]]; then
    IFS=$TAB read -r model used tended < <(tail -n 80 -- $tp | jq -Rrs '
      [split("\n")[] | fromjson? | select(.isSidechain != true)] as $r
      | ([$r[] | select(.type == "assistant" and .message.usage != null)] | last) as $a
      | ([$r[] | select(.type == "user" or .type == "assistant" or (.type == "system" and .subtype == "turn_duration"))] | last) as $l
      | [ ($a.message.model // ""),
          ($a.message.usage // {} | (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)),
          (if $l == null then "" elif $l.type == "system" then 1
           elif $l.type == "user" and ($l.message.content | tostring | test("\\[Request interrupted by user")) then 1
           else "" end) ] | @tsv' 2>/dev/null)
    # Claude 5 models and Opus 4.6+/Sonnet 4.6 have a 1M window, older ones 200K
    case $model in
      *'[1m]'*|claude-(fable|mythos|opus|sonnet|haiku)-5*|claude-opus-4-[678]*|claude-sonnet-4-6*) win=1000000 ;;
      *) win=200000 ;;
    esac
    (( ${used:-0} > win )) && win=1000000
    (( ${used:-0} > 0 )) && tctx=$(( used * 100 / win ))
    tcache[$tp]="$mt$US$tctx$US$tended"
  fi
  IFS=$US read -r _ tctx tended <<< "${tcache[$tp]}"
}

# ── sessions: one row per claude pane (+ hook-reported sessions elsewhere) ──
rows=(); rowpane=(); top=idle
refresh_sessions() {
  local f ts st pane cwd det topic tpath sid sctx name now=$EPOCHSECONDS tctx tended
  local -A byp; local -a recs
  # newest hook file per pane wins; drop files for panes that are gone
  for f in "$SDIR"/*(N.om); do
    IFS=$US read -r ts st pane cwd det topic tpath < "$f" 2>/dev/null || continue
    if [[ -n "$pane" ]]; then
      own_pane "$pane" || continue            # another terminal's session: not ours to show or prune
      if [[ ${#alive} -gt 0 && -z "${alive[$pane]}" ]] || [[ -n ${byp[$pane]} ]]; then rm -f "$f"; continue; fi
      byp[$pane]="$ts$US$st$US$cwd$US$det$US$topic$US$tpath$US${f:t}"
    elif (( now - ts < 6*3600 )); then
      byp[nopane-${f:t}]="$ts$US$st$US$cwd$US$det$US$topic$US$tpath$US${f:t}"
    fi
  done
  # claude panes the hook hasn't reported yet: infer from the title glyph
  for pane in ${(k)claudepane}; do
    [[ -n ${byp[$pane]} ]] && continue
    if [[ $BACKEND == generic || ${ptitle[$pane]} == ✳* ]]; then byp[$pane]="$now${US}idle$US${pcwd[$pane]}${US}no activity yet$US"
    else byp[$pane]="$now${US}working$US${US}busy$US"; fi
  done
  top=idle; quiet=999999
  for pane in ${(k)byp}; do
    [[ -n $MYPANE && -z ${mine[$pane]} ]] && continue        # another tab's session
    IFS=$US read -r ts st cwd det topic tpath sid <<< "${byp[$pane]}"
    # old records of Claude's "waiting for your input" nudge aren't real requests
    [[ $st == waiting && $det == "Claude is waiting for your input" ]] && { st=done; det="finished"; }
    transcript_info "$tpath"
    # Claude Code's own figure (via the status line) beats our estimate
    if [[ -n $sid && -r $STATE/status/$sid ]]; then
      IFS=$US read -r _ sctx _ < $STATE/status/$sid; [[ -n $sctx ]] && tctx=$sctx
    fi
    # the transcript says the turn is over: whatever a late hook said, it's done
    # (give a new prompt a moment to reach the transcript first)
    [[ $st != (idle|done) && -n $tended ]] && (( now - ts > 10 )) && { st=done; det="finished"; }
    [[ $st == done ]] && (( now - ts > 600 )) && st=idle
    if [[ ( $st == done || $st == idle ) ]] && (( ${bgcount[$pane]:-0} > 0 )); then
      st=bg; det="${bgcount[$pane]} background task$( (( bgcount[$pane] > 1 )) && print -n s) running"
    fi
    [[ $st == idle || $st == done ]] && (( now - ts < quiet )) && quiet=$(( now - ts ))
    [[ $st != idle && $st != done ]] && quiet=0
    # frog reacts to a session changing state
    if [[ -n ${oldst[$pane]} && ${oldst[$pane]} != $st ]]; then
      case $st in
        error)   start_ev dead 32 ;;
        done)    [[ $ev != dead ]] && start_ev yay 20 ;;
        waiting) [[ $ev != dead ]] && start_ev alert 14 ;;
      esac
    fi
    oldst[$pane]=$st
    (( PRI[$st] > PRI[$top] )) && top=$st
    # name: Claude's title for the conversation (read from the terminal where it
    # lets us, else from the transcript via the hook), else the start of the
    # latest prompt. A pane Claude hasn't titled yet is just "Claude Code".
    name=${ptitle[$pane]}
    [[ $name == [^[:alnum:]]\ * ]] && name=${name#* }     # drop Claude's spinner glyph
    [[ $name == (|claude|Claude|Claude Code) ]] && name=$topic
    [[ -z $name ]] && name="new session"
    recs+=("${PRI[$st]}$US$ts$US$st$US$name$US$det$US$((now - ts))$US${pane#nopane-*}$US$tctx")
  done
  rows=("${(@On)recs}")      # most urgent first, then most recent
}

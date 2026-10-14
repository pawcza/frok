# render.zsh — one frame: the pet and the sessions beside it, then the footer
# (fact, stats, limits, keys, tricks), drawn only where it changed.

draw_frame() {
  (( tick % 10 == 0 )) && { refresh_panes; update_size; }
  (( tick % 5 == 0 ))  && refresh_sessions
  (( blink = (tick % 22) < 2 ))
  d="..."; dots=${d[1,(tick/3)%4]}
  ec=${COL[$top]:-$G}
  # Up to 4 sessions (two lines each) sit right of the frog; below them the
  # fact, the pane keys and the frog's tricks span the full width. Narrow
  # panes put the sessions under the frog instead.
  (( fw = ${COLUMNS:-120} - 1 ))
  (( stacked = ${COLUMNS:-120} < 75 ))
  if (( stacked )); then iw=$fw; sess_off=9; else (( iw = ${COLUMNS:-120} - 35 )); sess_off=0; fi

  # sessions, 4 to a page; each with focus / close buttons on the right
  sess=(); rowpane=(); btns=(); pager=""
  (( sesscol = stacked ? 1 : 36 ))
  (( npg = (${#rows} + 3) / 4, npg < 1 && (npg = 1), pg > npg && (pg = npg), pg < 1 && (pg = 1) ))
  (( confirm_until < tick )) && confirm=""
  if (( ${#rows} == 0 )); then
    sess+=("${D}✶ no Claude sessions running${X}"); rowpane+=("")
  else
    for r in "${(@)rows[(pg - 1) * 4 + 1, pg * 4]}"; do
      IFS=$US read -r _ _ st name det age pane pct <<< "$r"
      c=${COL[$st]:-$W}; lab=${LAB[$st]:-$st}
      [[ $st == working || $st == thinking ]] && lab="$lab$dots"
      when=$(ago $age); [[ $det == "no activity yet" || $det == busy ]] && when=""
      # buttons: focus when we can reach the pane, close when we know its claude
      canfocus=0; own_pane "$pane" && { [[ $BACKEND != generic ]] || [[ -n ${wtpane[$pane]} ]]; } && canfocus=1
      canclose=0; [[ -n ${panepid[$pane]} ]] && canclose=1
      bt=""; (( btw = 0 ))
      (( canfocus )) && { bt+="${KB} focus ${X}"; (( btw += 7 )); }
      if (( canclose )); then
        (( btw )) && { bt+=" "; (( btw += 1 )); }
        if [[ $confirm == $pane ]]; then bt+="${R}"$'\e[7m'" sure? ${X}"; (( btw += 7 )); cl=7
        else bt+="${KB} ✕ ${X}"; (( btw += 3 )); cl=3; fi
      fi
      head=$(cut_to "$name" $(( iw - 6 - btw )))
      if [[ -n $focused && $pane == $focused ]]; then line="${c}●${X} ${KB}${ACC}"$'\e[1m'" ${head} ${X}"; (( vis = 4 + ${#head} ))   # the pane you're in
      else line="${c}●${X} ${W}${head}${X}"; (( vis = 2 + ${#head} )); fi
      if (( btw )); then
        (( gap = iw - vis - btw, gap < 1 && (gap = 1) ))
        line+="${(l:gap:)}$bt"
        (( bx = sesscol + vis + gap ))      # screen column where the buttons start
        fx=""; (( canfocus )) && fx="$bx:$(( bx + 6 ))"
        cx=""; (( canclose )) && cx="$(( bx + btw - cl )):$(( bx + btw - 1 ))"
        btns[$(( ${#sess} + 1 ))]="$fx/$cx/$pane"
      fi
      sess+=("$line")
      # second line is a table — ctx bar │ status │ age │ detail — fixed widths,
      # so a growing "thinking..." or age never shifts what follows
      if [[ -n $pct ]]; then                 # context window used
        sub="${D}ctx: ${X}$(bar $pct)"
      else sub="${(l:20:)}"; fi
      sub+="  ${c}${(r:11:)lab}${X}  ${D}${(l:3:)when}${X}"
      [[ -n $det ]] && sub+="  ${D}$(cut_to "$det" $(( iw - 2 - 20 - 2 - 11 - 2 - 3 - 2 )))${X}"
      sess+=("  $sub")
      rowpane+=("$pane" "$pane")
    done
    if (( npg > 1 )); then                   # pager: ‹ prev · page n/m · next ›
      pv="‹ prev"; nx="next ›"; pt="page $pg/$npg"
      (( pg > 1 )) && pvs="${KB} $pv ${X}" || pvs="${D} $pv ${X}"
      (( pg < npg )) && nxs="${KB} $nx ${X}" || nxs="${D} $nx ${X}"
      sess+=("$pvs  ${D}$pt${X}  $nxs"); rowpane+=("")
      pager="${#sess}/$sesscol:$(( sesscol + 7 ))/$(( sesscol + 8 + 2 + ${#pt} + 2 )):$(( sesscol + 8 + 2 + ${#pt} + 2 + 7 ))"
    fi
  fi

  (( tick % 300 == 0 )) && run_stats
  (( tick % 25 == 0 )) && { refresh_stats; refresh_limits; }
  (( cw = fw - LW ))
  fact=""; [[ -r $FACTFILE ]] && fact=$(< $FACTFILE); [[ -z "$fact" ]] && fact="fetching a useless fact…"
  [[ $FACTS == true ]] || fact="facts are off (frok companion facts on)"
  if [[ "$fact" != "$lastfact" || $fw -ne ${lastfw:-0} ]]; then
    flines=("${(@f)$(print -r -- "$fact" | fold -s -w $cw)}")
    pack $cw "${keyitems[@]}"; keylines=("${packed[@]}"); keypos=("${packpos[@]}")
    pack $cw "${trickitems[@]}"; tricklines=("${packed[@]}"); trickpos=("${packpos[@]}")
    lastfact=$fact; lastfw=$fw
  fi
  out=()
  hint="space → new fact"
  fl=(); for fln in "${flines[@]}"; do fl+=("${L}${fln}${X}"); done
  if (( ${#flines[-1]} + 3 + ${#hint} <= cw )); then fl[-1]+="   ${D}${hint}${X}"; else fl+=("${D}${hint}${X}"); fi
  section fact "${fl[@]}"

  # stats: period tabs, then the numbers (on their own line when narrow)
  tabs=""; tabx=(); (( x = LW + 1 ))
  for (( k = 1; k <= 3; k++ )); do
    tabx+=("$x:$(( x + ${#plabel[k]} + 1 ))"); (( x += ${#plabel[k]} + 3 ))
    (( k == pi )) && tabs+="${KB}${ACC}"$'\e[1m'" ${plabel[k]} ${X} " || tabs+="${D} ${plabel[k]} ${X} "
  done
  (( tabw = 3 * 2 + ${#${(j::)plabel}} + 3 ))
  if (( ${#statvals} == 3 )); then
    IFS=$TAB read -r stok sadd sdel scom <<< "${statvals[pi]}"
    nums="${W}$(human $stok)${X}${D} tokens${X}   ${G}+$(human $sadd)${X} ${R}−$(human $sdel)${X}${D} lines${X}   ${W}${scom}${X}${D} commit$( (( scom == 1 )) || print -n s)${X}"
    numw=$(( ${#$(human $stok)} + 7 + 3 + ${#$(human $sadd)} + ${#$(human $sdel)} + 9 + 3 + ${#scom} + 8 ))
  else nums="${D}counting… (first pass reads all your transcripts)${X}"; numw=49; fi
  statsrow=$(( ${#out} + 1 ))
  if (( tabw + 2 + numw <= cw )); then section stats "$tabs  $nums"; else section stats "$tabs" "$nums"; fi

  if (( ${#lim} )); then
    lrow=""
    [[ -n ${lim[1]} ]] && { (( EPOCHSECONDS >= ${lim[2]:-0} )) && lim[1]=0
      lrow+="${D}5h ${X}$(bar ${lim[1]})${D}  resets in $(dur $(( ${lim[2]:-0} - EPOCHSECONDS )))${X}"; }
    [[ -n ${lim[3]} ]] && { (( EPOCHSECONDS >= ${lim[4]:-0} )) && lim[3]=0
      lrow+="${lrow:+     }${D}7d ${X}$(bar ${lim[3]})${D}  resets $(strftime '%a %H:%M' ${lim[4]:-0})${X}"; }
    section limits "$lrow"
  else
    section limits "${D}shows after Claude's next reply (needs a Pro/Max plan)${X}"
  fi
  keysrow=$(( ${#out} + 1 ))
  section keys "${keylines[@]}"
  tricksrow=$(( ${#out} + 1 ))
  section $PET_LABEL "${tricklines[@]}"

  build_frog
  # the frog sits in a frame the colour of the label chips
  frame=("${FB}▄${(l:31::▄:)}▄${X}")
  for (( i = 1; i <= 6; i++ )); do frame+=("${FB}█${X}${frogrow[$i]}${FB}█${X}"); done
  frame+=("${FB}▀${(l:31::▀:)}▀${X}")
  lines=()
  if (( stacked )); then
    lines=("${frame[@]}" "" "${sess[@]}")
  else
    (( th = ${#sess} > 8 ? ${#sess} : 8 ))
    for (( i = 1; i <= th; i++ )); do lines+=("${frame[$i]:-${(r:33:)}}  ${sess[$i]}"); done
  fi
  (( statsrow += ${#lines}, tricksrow += ${#lines}, keysrow += ${#lines} ))
  lines+=("${out[@]}")
  for (( i = 1; i <= ${LINES:-8}; i++ )); do
    row=${lines[$i]}
    if [[ "$row" != "${prev[$i]}" ]]; then
      print -rn -- $'\e['"$i;1H$row"$'\e[K'
      prev[$i]=$row
    fi
  done

}

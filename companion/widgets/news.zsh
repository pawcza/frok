# news — headlines from Hacker News or RSS / Atom feeds; N or a click on › for the next, click a headline to open it. Options: feeds ("hn" and/or feed URLs, comma-separated), lines (1-3).
# options: feeds lines
W_LABEL[news]=news; W_KEYS[N]=news

w_news_i=1; w_news_items=(); w_news_mtime=""
w_news_refresh() {
  local f=$WSTATE/news.tsv feeds=$(wopt news feeds hn)
  [[ -z ${FROK_DEMO-} ]] || { w_news_load; return; }
  local -a m; zstat -A m +mtime -- $f 2>/dev/null
  local had=""; [[ -r $f.feeds ]] && had=$(<$f.feeds)
  if [[ ! -s $f || $had != $feeds ]] || (( EPOCHSECONDS - ${m[1]:-0} > 900 )); then
    [[ -e $f.lock ]] || { : >| $f.lock
      { python3 $HERE/widgets/news-fetch.py "$feeds" > $f.tmp 2>/dev/null && [[ -s $f.tmp ]] && mv -f $f.tmp $f && print -r -- $feeds >| $f.feeds
        rm -f $f.lock $f.tmp; } &! }
  fi
  w_news_load
  (( tick % 50 == 0 && tick > 0 )) && w_news_next     # a new headline every ~10 s
}
w_news_load() {
  local f=$WSTATE/news.tsv; local -a m; zstat -A m +mtime -- $f 2>/dev/null
  [[ ${m[1]-} == $w_news_mtime ]] && return
  w_news_mtime=${m[1]-}; w_news_items=(); [[ -r $f ]] && w_news_items=(${(f)"$(<$f)"}); w_news_i=1
}
w_news_next() { (( ${#w_news_items} )) && (( w_news_i = w_news_i % ${#w_news_items} + 1 )); }
w_news_key() { w_news_next; }
w_news_click() { [[ $1 == next ]] && { w_news_next; return; }; open_url "${${w_news_items[$1]}##*$TAB}"; }

w_news_render() {
  if (( ! ${#w_news_items} )); then
    (( $+commands[python3] )) && wl=("${D}fetching headlines…${X}") || wl=("${D}needs python3 for feeds${X}")
    return
  fi
  local n=$(wopt news lines 1) k i item title src
  for (( k = 0; k < n && k < ${#w_news_items}; k++ )); do
    (( i = (w_news_i - 1 + k) % ${#w_news_items} + 1 ))
    item=${w_news_items[i]}; src=${item%%$TAB*}; title=${${item#*$TAB}%%$TAB*}
    title=$(cut_to "$(clean "$title")" $(( cw - ${#src} - 8 )))
    wl+=("${D}${src}${X}  ${W}${title}${X}")
    wclick+=("$(( k + 1 )):$(( ${#src} + 3 )):$(( ${#src} + 2 + ${#title} )):$i")
  done
  wl[1]+="  ${KB} › ${X}"; wclick+=("1:$(( ${#src} + ${#title} + 5 )):$(( ${#src} + ${#title} + 7 )):next")
}

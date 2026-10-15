# fact — a useless fact from the internet; space (or a click) for another.
W_LABEL[fact]=fact; W_KEYS[" "]=fact

FACTFILE="${TMPDIR:-/tmp}/frok-companion-fact.$$"
FACTLOCK="$FACTFILE.lock"
FACT_URL="https://uselessfacts.jsph.pl/api/v2/facts/random?language=en"
FACTS=${FROK_FACTS:-true}
fetch_fact() {             # one fetch in flight at a time, in the background
  [[ $FACTS == true ]] || return
  [[ -n ${FROK_DEMO_FACT-} ]] && { printf '%s' "$FROK_DEMO_FACT" >| "$FACTFILE"; return; }
  [[ -e "$FACTLOCK" ]] && return
  : >| "$FACTLOCK"
  printf '%s' "fetching a new fact…" >| "$FACTFILE"
  {
    local t
    t=$(curl -s --max-time 5 "$FACT_URL" 2>/dev/null | jq -r '.text // empty' 2>/dev/null)
    [[ -n "$t" ]] && printf '%s' "$t" >| "$FACTFILE"
    rm -f "$FACTLOCK"
  } &!
}
w_fact_init() { [[ -s $FACTFILE ]] || fetch_fact; }
w_fact_key() { fetch_fact; }
w_fact_click() { fetch_fact; }

w_fact_render() {
  local fact="" hint="space → new fact"
  [[ -r $FACTFILE ]] && fact=$(clean "$(< $FACTFILE)"); [[ -z $fact ]] && fact="fetching a useless fact…"
  [[ $FACTS == true ]] || fact="facts are off (frok companion facts on)"
  if [[ $fact != ${w_fact_last-} || $cw != ${w_fact_w-} ]]; then
    w_fact_lines=("${(@f)$(print -r -- "$fact" | fold -s -w $cw)}"); w_fact_last=$fact; w_fact_w=$cw
  fi
  local l; for l in "${w_fact_lines[@]}"; do wl+=("${L}${l}${X}"); done
  if (( ${#w_fact_lines[-1]} + 3 + ${#hint} <= cw )); then wl[-1]+="   ${D}${hint}${X}"; else wl+=("${D}${hint}${X}"); fi
  wclick+=("${#wl}:1:${cw}:new")
}

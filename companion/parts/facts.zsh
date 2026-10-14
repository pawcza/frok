# facts.zsh — useless facts, fetched in the background.

# ── useless facts (fetched in the background, one in flight at a time) ──
FACTFILE="${TMPDIR:-/tmp}/frok-companion-fact.$$"
FACTLOCK="$FACTFILE.lock"
FACT_URL="https://uselessfacts.jsph.pl/api/v2/facts/random?language=en"
FACTS=${FROK_FACTS:-true}
fetch_fact() {
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

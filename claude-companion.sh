#!/bin/zsh
# claude-companion — live animated terminal pet that watches your Claude Code
# sessions. Sessions are discovered from WezTerm panes running `claude`, and
# enriched by each session's hook (companion-event.sh → sessions/<id>) with
# what it is doing. The frog's mood follows the most urgent session.
# Click a session row to focus its pane. Space → new useless fact. Letter keys
# make the frog do tricks (f w g l r t y x d z). Ctrl+C quits.
emulate -L zsh
setopt extendedglob
zmodload zsh/datetime 2>/dev/null
HERE=${0:A:h}                       # files live next to this script (symlinks resolved)
SDIR="$HERE/sessions"
WZ=/Applications/WezTerm.app/Contents/MacOS/wezterm; [[ -x $WZ ]] || WZ=wezterm
KT=/Applications/kitty.app/Contents/MacOS/kitten;     [[ -x $KT ]] || KT=kitten
# Which terminal are we in? Each companion lists, focuses and prunes only its
# own terminal's sessions (WezTerm panes are plain ids, kitty windows are k<id>).
# "generic" = any other terminal (Windows Terminal/WSL, iTerm, Terminal.app…):
# sessions are found by tty, named after their folder, and can't be focused.
if [[ $TERM == xterm-kitty && -n $KITTY_WINDOW_ID ]]; then BACKEND=kitty
elif [[ -n $WEZTERM_PANE ]]; then BACKEND=wezterm
else BACKEND=generic; fi
own_pane() {
  case $BACKEND in
    kitty)   [[ $1 == k<-> ]] ;;
    wezterm) [[ $1 == <-> ]] ;;
    *)       [[ $1 == t:* ]] ;;
  esac
}
focus_pane() {
  [[ $BACKEND == generic ]] && return     # no terminal API to focus a pane
  if [[ $BACKEND == kitty ]]; then $KT @ focus-window --match "id:${1#k}" >/dev/null 2>&1 &!
  else $WZ cli activate-pane --pane-id "$1" >/dev/null 2>&1 &!; fi
}
US=$'\x1f'; TAB=$'\t'

# Colours come from the terminal's own ANSI palette, so the companion follows
# whatever scheme WezTerm uses (currently Tokyo Night).
G=$'\e[32m'; L=$'\e[34m'; D=$'\e[90m'; W=$'\e[39m'
Y=$'\e[33m'; C=$'\e[36m'; R=$'\e[31m'; M=$'\e[35m'; X=$'\e[0m'

# ── useless facts (fetched in the background, one in flight at a time) ──
FACTFILE="${TMPDIR:-/tmp}/claude-companion-fact.$$"
FACTLOCK="$FACTFILE.lock"
FACT_URL="https://uselessfacts.jsph.pl/api/v2/facts/random?language=en"
fetch_fact() {
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
fetch_fact

# hide cursor + SGR mouse reporting (clicks arrive as \e[<b;x;yM). Echo stays
# off for the whole run, otherwise mouse/scroll reports that land between reads
# get printed onto the screen (e.g. "[[<64;70;5M" when scrolling).
STTY_SAVED=$(stty -g 2>/dev/null)
[[ -t 0 ]] && stty -echo -icanon 2>/dev/null
cleanup() { print -n $'\e[?1000l\e[?1006l\e[?25h\e[2J\e[H'"$X"; [[ -n $STTY_SAVED ]] && stty "$STTY_SAVED" 2>/dev/null; rm -f "$FACTFILE" "$FACTLOCK" 2>/dev/null; exit 0 }
trap cleanup INT TERM
print -n $'\e[2J\e[?25l\e[?1000h\e[?1006h'

frog=("${(@f)$(< $HERE/frog.txt)}")

typeset -A PRI=(waiting 7 error 6 working 5 dizzy 4 thinking 3 bg 2 done 1 idle 0)
typeset -A COL=(waiting $Y error $R working $C dizzy $M thinking $L bg $C done $G idle $G)
typeset -A LAB=(waiting "needs you" error "error" working "working" dizzy "compacting" thinking "thinking" bg "background" done "done" idle "idle")

ago() { local s=$1; (( s < 60 )) && { print -n "${s}s"; return }; (( s < 3600 )) && { print -n "$((s/60))m"; return }; print -n "$((s/3600))h"; }
cut_to() { local s=$1 n=$2; (( n < 2 )) && n=2; (( ${#s} > n )) && s="${s[1,n-1]}…"; print -rn -- "$s"; }

# ── panes: titles, ttys, and which ones run claude (refreshed every ~2s) ──
typeset -A ptitle claudepane bgcount alive pcwd
refresh_generic() {
  local -a w pslines; local -A cpane; local line
  pslines=("${(@f)$(ps -Ao pid=,ppid=,tty=,args= 2>/dev/null)}")
  for line in "${pslines[@]}"; do
    w=(${=line})
    # native `claude`, or npm's `node …/claude-code/cli.js` (common on Linux/WSL)
    [[ ( ${w[4]} == (*/|)claude || ${w[5]} == *claude-code/cli.js ) && ${w[3]} != (\?|\?\?|-) ]] || continue
    claudepane[t:${w[3]}]=1; alive[t:${w[3]}]=1; cpane[${w[1]}]=t:${w[3]}
    # its working folder names the session (Linux/WSL: /proc, macOS: lsof)
    if [[ -e /proc/${w[1]}/cwd ]]; then pcwd[t:${w[3]}]=${$(readlink /proc/${w[1]}/cwd 2>/dev/null):t}
    else pcwd[t:${w[3]}]=${${(M)${(f)"$(lsof -a -p ${w[1]} -d cwd -Fn 2>/dev/null)"}:#n*}#n}; pcwd[t:${w[3]}]=${pcwd[t:${w[3]}]:t}; fi
  done
  for line in "${pslines[@]}"; do
    w=(${=line})
    [[ -n ${cpane[${w[2]}]} && ${${w[4]}#-} == (*/|)(zsh|bash|sh) ]] && (( bgcount[${cpane[${w[2]}]}]++ ))
  done
}

refresh_panes() {
  ptitle=(); claudepane=(); bgcount=(); alive=()
  if [[ $BACKEND == generic ]]; then refresh_generic; return; fi
  if [[ $BACKEND == kitty ]]; then
    local kl kid kc kt
    for kl in "${(@f)$($KT @ ls 2>/dev/null | jq -r '.[].tabs[].windows[] |
        "k\(.id)\t\([.foreground_processes[]?.cmdline[0]? // "" | split("/") | last] | index("claude") != null)\t\(.title)"' 2>/dev/null)}"; do
      [[ -z "$kl" ]] && continue
      kid=${kl%%$TAB*}; kl=${kl#*$TAB}; kc=${kl%%$TAB*}; kt=${kl#*$TAB}
      ptitle[$kid]=$kt; alive[$kid]=1; [[ $kc == true ]] && claudepane[$kid]=1
    done
    return
  fi
  local -A ttypane; local line id tty title
  for line in "${(@f)$($WZ cli list --format json 2>/dev/null | jq -r '.[] | "\(.pane_id)\t\(.tty_name)\t\(.title)"' 2>/dev/null)}"; do
    [[ -z "$line" ]] && continue
    id=${line%%$TAB*}; line=${line#*$TAB}; tty=${${line%%$TAB*}#/dev/}; title=${line#*$TAB}
    ptitle[$id]=$title; alive[$id]=1; ttypane[$tty]=$id
  done
  # claude processes per pane, and the shells they're running: a finished turn
  # that still has shell children is running background tasks
  local -a w; local -A cpane
  local -a pslines; pslines=("${(@f)$(ps -Ao pid=,ppid=,tty=,comm= 2>/dev/null)}")
  for line in "${pslines[@]}"; do
    w=(${=line})
    [[ ${w[4]} == (*/|)claude && -n ${ttypane[${w[3]}]} ]] || continue
    claudepane[${ttypane[${w[3]}]}]=1; cpane[${w[1]}]=${ttypane[${w[3]}]}
  done
  for line in "${pslines[@]}"; do
    w=(${=line})
    [[ -n ${cpane[${w[2]}]} && ${w[4]} == (*/|)(zsh|bash|sh) ]] && (( bgcount[${cpane[${w[2]}]}]++ ))
  done
}

# ── sessions: one row per claude pane (+ hook-reported sessions elsewhere) ──
rows=(); rowpane=(); top=idle
refresh_sessions() {
  local f ts st pane cwd det name now=$EPOCHSECONDS
  local -A byp; local -a recs
  # newest hook file per pane wins; drop files for panes that are gone
  for f in "$SDIR"/*(N.om); do
    IFS=$US read -r ts st pane cwd det < "$f" 2>/dev/null || continue
    if [[ -n "$pane" ]]; then
      own_pane "$pane" || continue            # another terminal's session: not ours to show or prune
      if [[ ${#alive} -gt 0 && -z "${alive[$pane]}" ]] || [[ -n ${byp[$pane]} ]]; then rm -f "$f"; continue; fi
      byp[$pane]="$ts$US$st$US$cwd$US$det"
    elif (( now - ts < 6*3600 )); then
      byp[nopane-${f:t}]="$ts$US$st$US$cwd$US$det"
    fi
  done
  # claude panes the hook hasn't reported yet: infer from the title glyph
  for pane in ${(k)claudepane}; do
    [[ -n ${byp[$pane]} ]] && continue
    if [[ $BACKEND == generic || ${ptitle[$pane]} == ✳* ]]; then byp[$pane]="$now${US}idle$US${pcwd[$pane]}${US}no activity yet"
    else byp[$pane]="$now${US}working$US${US}busy"; fi
  done
  top=idle; quiet=999999
  for pane in ${(k)byp}; do
    IFS=$US read -r ts st cwd det <<< "${byp[$pane]}"
    # old records of Claude's "waiting for your input" nudge aren't real requests
    [[ $st == waiting && $det == "Claude is waiting for your input" ]] && { st=done; det="finished"; }
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
    name=${ptitle[$pane]:-${cwd:t}}
    [[ $name == [^[:alnum:]]\ * ]] && name=${name#* }   # drop Claude's spinner glyph
    [[ -z $name ]] && name="claude"
    recs+=("${PRI[$st]}$US$ts$US$st$US$name$US$det$US$((now - ts))$US${pane#nopane-*}")
  done
  rows=("${(@On)recs}")      # most urgent first, then most recent
}

# Track the pane size ourselves: a script doesn't get LINES/COLUMNS updates, and
# panes are often resized right after launch (kitty lays out after spawning).
update_size() {
  local sz; sz=$(stty size 2>/dev/null) || return
  local l=${sz% *} c=${sz#* }
  if [[ $l != $LINES || $c != $COLUMNS ]]; then
    LINES=$l; COLUMNS=$c; prev=(); print -n $'\e[2J'      # full repaint at the new size
  fi
}
TRAPWINCH() { update_size }


# ── frog animation ────────────────────────────────────────────────────
# The frog's face follows the most urgent session; state changes trigger short
# reactions (error → x_x + shiver, done → yay, needs you → alert) and, when
# nothing's happening, it does random tricks. Everything stays in fixed cells.
typeset -A oldst
ev=""; ev_until=0; flx=4; fly=2; quiet=0
annoy=0; last_click=0; phase=""; phase_t=0   # clicks on the frog annoy her
start_ev() { ev=$1; ev_until=$(( tick + $2 )); }
tricks=(wink googly look roll tongue fly fly)
spin=('|' '/' '-' '\'); qs=('?' '..' '...'); dz=('@' 'o' 'O' 'o')
# split the art once: eyes are the two ' on row 2, the mouth is '-----' on row 4
Q="'"; MOUTH0="'-----'"
eyeA=${frog[2]%%$Q*}; eyeR=${frog[2]#*$Q}; eyeB=${eyeR%%$Q*}; eyeC=${eyeR#*$Q}
mouA=${frog[4]%%$MOUTH0*}; mouC=${frog[4]#*$MOUTH0}

build_frog() {
  local e1="'" e2="'" mouth=$MOUTH0 bub="" bc=$Y shx=0 off=0 fc=$ec left
  local -a marg mc; marg=("" "" ""); mc=($Y $W $W)
  (( tick >= ev_until )) && ev=""
  if [[ -z $ev && -z $phase && ( $top == idle || $top == done || $top == bg ) ]] && (( annoy == 0 && quiet <= 600 && RANDOM % 110 == 0 )); then
    local t=${tricks[RANDOM % ${#tricks} + 1]}
    case $t in
      fly)  start_ev fly 30; flx=$(( RANDOM % 8 + 1 )); fly=$(( RANDOM % 2 + 2 )) ;;
      roll) start_ev roll 12 ;;
      *)    start_ev $t 9 ;;
    esac
  fi
  # base expression from the most urgent session
  case $top in
    working)  e1='>'; e2='<'; (( (tick/2) % 2 )) && mouth="'--o--'"; bub=${spin[tick % 4 + 1]} ;;
    thinking) (( (tick/6) % 2 )) && { e1='.'; e2='.'; }; bub=${qs[(tick/3) % 3 + 1]} ;;
    waiting)  e1='O'; e2='O'; mouth="'--O--'"; (( (tick/3) % 2 )) && bub='!' ;;
    error)    e1='x'; e2='x'; mouth="'--u--'"; bub='x_x'; bc=$R ;;
    dizzy)    e1=${dz[tick % 4 + 1]}; e2=${dz[(tick + 2) % 4 + 1]}; bub='~' ;;
    done)     e1='^'; e2='^'; mouth="'\___/'" ;;
    bg)       bub=${qs[(tick/4) % 3 + 1]} ;;
  esac
  # dozing off after 10 quiet minutes
  if [[ $top == idle ]] && (( quiet > 600 )) && [[ -z $ev ]]; then
    e1='-'; e2='-'; bub=""
    local zr=$(( 3 - (tick / 5) % 3 )); marg[$zr]="${(l:$((7 - zr)):)}${${:-z Z z}[$(( (tick / 5) % 3 * 2 + 1 ))]}"; mc[$zr]=$D
  fi
  # short reactions and tricks override the base face
  left=$(( ev_until - tick ))
  case $ev in
    dead)   e1='x'; e2='x'; mouth="'--u--'"; bub='x_x'; bc=$R; (( left > 18 && tick % 2 )) && shx=1 ;;
    yay)    e1='^'; e2='^'; mouth="'\___/'"; (( (tick/2) % 2 )) && bub='yay!' || bub='\o/'
            marg[2]="${(l:$(( RANDOM % 6 + 1 )):)}*"; mc[2]=$Y; marg[3]="${(l:$(( RANDOM % 7 + 1 )):)}+"; mc[3]=$Y ;;
    alert)  e1='O'; e2='O'; mouth="'--O--'"; bub='!!' ;;
    wink)   e1='-' ;;
    googly) e1='O'; e2='.' ;;
    look)   (( left > 4 )) && { e1='.'; e2="'"; } || { e1="'"; e2='.'; } ;;
    roll)   local rl=("'" '.' ',' '.'); e1=${rl[left % 4 + 1]}; e2=$e1 ;;
    tongue) mouth="'--p--'"; bub=':P' ;;
    dizzy)  e1=${dz[tick % 4 + 1]}; e2=${dz[(tick + 2) % 4 + 1]}; bub='~@~' ;;
    nap)    e1='-'; e2='-'; bub=""
            local nr=$(( 3 - (tick / 4) % 3 )); marg[$nr]="${(l:$((7 - nr)):)}${${:-z Z z}[$(( (tick / 4) % 3 * 2 + 1 ))]}"; mc[$nr]=$D ;;
    fly)    if (( left > 8 )); then                      # fly buzzing about, frog watching it
              flx=$(( flx + RANDOM % 3 - 1 )); (( flx < 1 )) && flx=1; (( flx > 8 )) && flx=8
              (( RANDOM % 3 == 0 )) && fly=$(( fly == 2 ? 3 : 2 ))
              marg[$fly]="${(l:$((flx - 1)):)}*"; mc[$fly]=$W; e1='o'; e2='o'
            elif (( left > 5 )); then mouth="'--O--'"; e1='O'; e2='O'   # snap!
            else mouth="'\___/'"; e1='^'; e2='^'; bub='gulp'; fi ;;
  esac
  # ── annoyance (clicks on the frog), overrides everything ─────────────
  (( annoy > 0 && tick - last_click > 15 && tick % 15 == 0 )) && (( annoy-- ))
  if [[ -z $phase ]] && (( annoy > 0 )); then
    if   (( annoy <= 2 )); then e1="'"; e2='-'; bub='hey!'
    elif (( annoy <= 4 )); then e1='='; e2='='; mouth=$MOUTH0; bub='stop it'
    elif (( annoy <= 6 )); then e1='\'; e2='/'; mouth="'^^^^^'"; bub='grr'; bc=$R; fc=$R; (( tick % 2 )) && shx=1
    elif (( annoy <= 9 )); then e1='\'; e2='/'; mouth="'#####'"; (( (tick/2) % 2 )) && bub='GRRR' || bub='!!!'
                               bc=$R; (( tick % 2 )) && fc=$R || fc=$Y; shx=$(( RANDOM % 3 ))
    else                        e1='@'; e2='@'; mouth="'#####'"; bub='ENOUGH'; bc=$R; fc=$R; shx=$(( RANDOM % 4 )); fi
  fi
  if [[ -n $phase ]]; then
    local pt=$(( tick - phase_t ))
    case $phase in
      bye)   e1='-'; e2='-'; mouth=$MOUTH0; bub='bye.'; bc=$D; fc=$ec
             (( pt >= 10 )) && { phase=leave; phase_t=$tick; } ;;
      leave) off=$(( pt * 2 )); (( off >= 31 )) && { off=31; phase=gone; phase_t=$tick; } ;;
      gone)  off=31; (( pt >= 125 )) && { phase=back; phase_t=$tick; } ;;
      back)  off=$(( 31 - pt * 2 )); (( off <= 0 )) && { off=0; phase=hmph; phase_t=$tick; } ;;
      hmph)  e1='-'; e2="'"; bub='hmph.'; bc=$D; (( pt >= 25 )) && { phase=""; annoy=0; } ;;
    esac
  fi

  # occasional blink when calm
  [[ -z $ev && -z $phase && annoy -eq 0 && ( $top == idle || $top == bg ) && $e1 == "'" ]] && (( blink )) && { e1='-'; e2='-'; }
  [[ -n $bub ]] && { marg[1]="${(l:8:)bub}"; mc[1]=$bc; }

  local -a art
  art=( "${frog[1]}" "${eyeA}${e1}${eyeB}${e2}${eyeC}" "${frog[3]}" "${mouA}${mouth}${mouC}" "${frog[5]}" "${frog[6]}" )
  local sp="${(l:shx:)}"
  frogrow=()
  if (( off > 0 )); then                         # sliding away / back in, or gone
    for i in {1..6}; do frogrow[$i]="${fc}${(r:31:)${art[$i][off+1,-1]}}${X}"; done
    if [[ $phase == gone ]]; then
      frogrow[3]="${D}${(r:31:):-       (she left)}${X}"
      frogrow[6]="${D}${(r:31:):-  .   .   .   .}${X}"
    fi
    return
  fi
  for i in 1 2 3; do frogrow[$i]="${mc[$i]}${(r:9:)marg[$i]}${X}${fc}${(r:22:)${:-$sp${art[$i][10,-1]}}}${X}"; done
  frogrow[4]="${(r:8:)}${fc}${(r:23:)${:-$sp${art[4][9,-1]}}}${X}"
  for i in 5 6; do frogrow[$i]="${fc}${(r:31:)${:-$sp${art[$i]}}}${X}"; done
}

typeset -a prev frogrow; tick=0; lastfact=""; factrow=0; factend=0
update_size; refresh_panes; refresh_sessions
while true; do
  (( tick % 10 == 0 )) && { refresh_panes; update_size; }
  (( tick % 5 == 0 ))  && refresh_sessions
  (( blink = (tick % 22) < 2 ))
  d="..."; dots=${d[1,(tick/3)%4]}
  ec=${COL[$top]:-$G}
  (( iw = ${COLUMNS:-120} - 33 )); (( iw < 40 )) && iw=40

  # sessions, then the fact (wrapped, never truncated), then hotkeys —
  # stacked down the pane's full height; the frog sits in rows 1-6.
  info=(); rowpane=()
  if (( ${#rows} == 0 )); then
    info+=("${D}✶ no Claude sessions running${X}"); rowpane+=("")
  else
    nw=10
    for r in "${rows[@]}"; do IFS=$US read -r _ _ _ name _ _ _ <<< "$r"; (( ${#name} > nw )) && nw=${#name}; done
    (( nw > 50 )) && nw=50
    n=0; max=4; (( ${#rows} > 4 )) && max=3
    for r in "${rows[@]}"; do
      (( ++n > max )) && break
      IFS=$US read -r _ _ st name det age pane <<< "$r"
      c=${COL[$st]:-$W}; lab=${LAB[$st]:-$st}
      [[ $st == working || $st == thinking ]] && lab="$lab$dots"
      when=$(ago $age); [[ $det == "no activity yet" || $det == busy ]] && when=""
      head=$(cut_to "$name" $nw)
      (( rest = iw - nw - 2 - 13 - ${#when} - 4 ))
      info+=("${c}●${X} ${W}${(r:nw:)head}${X}  ${c}${(r:12:)lab}${X} ${D}$(cut_to "$det" $rest)${X}  ${D}${when}${X}")
      rowpane+=("$pane")
    done
    (( ${#rows} > 4 )) && { info+=("${D}  + $(( ${#rows} - 3 )) more session(s)${X}"); rowpane+=(""); }
  fi
  factrow=$(( ${#info} + 1 ))
  fact=$(< "$FACTFILE" 2>/dev/null); [[ -z "$fact" ]] && fact="fetching a useless fact…"
  if [[ "$fact" != "$lastfact" || $iw -ne ${lastiw:-0} ]]; then
    flines=("${(@f)$(print -r -- "$fact" | fold -s -w $(( iw - 2 )))}")
    lastfact=$fact; lastiw=$iw
  fi
  hint="space → new fact"
  fout=("${Y}✶${X} ${L}${flines[1]}${X}")
  for fln in "${(@)flines[2,-1]}"; do fout+=("  ${L}${fln}${X}"); done
  if (( ${#flines[-1]} + 2 + 3 + ${#hint} <= iw )); then fout[-1]+="   ${D}${hint}${X}"
  else fout+=("  ${D}${hint}${X}"); fi
  info+=("${fout[@]}")
  factend=${#info}
  info+=("${C}⌘D${X}${D} split→${X}  ${C}⌘⇧D${X}${D} split↓${X}  ${C}⌘⌥←↑↓→${X}${D} move${X}  ${C}⌘⇧W${X}${D} close pane${X}")
  info+=("${D}frog: ${W}f${D} fly  ${W}w${D} wink  ${W}g${D} googly  ${W}l${D} look  ${W}r${D} roll  ${W}t${D} tongue  ${W}y${D} yay  ${W}x${D} dead  ${W}d${D} dizzy  ${W}z${D} nap${X}")

  (( nrows = ${#info} > 6 ? ${#info} : 6 ))
  (( nrows > ${LINES:-8} )) && nrows=${LINES:-8}     # never address rows past the pane bottom
  build_frog
  for (( i = 1; i <= ${LINES:-8}; i++ )); do
    if (( i <= nrows )); then row="${frogrow[$i]:-${(r:31:)}}${info[$i]}"; else row=""; fi
    if [[ "$row" != "${prev[$i]}" ]]; then
      print -rn -- $'\e['"$i;1H$row"$'\e[K'
      prev[$i]=$row
    fi
  done

  if [[ -t 0 ]]; then
    if read -t 0.18 -k 1 -s key 2>/dev/null; then
      buf=$key
      while read -t 0.01 -k 1 -s key 2>/dev/null; do buf+=$key; done   # rest of a multi-byte key / mouse report
      if [[ $buf == $'\e[<'(#b)([0-9]##)';'([0-9]##)';'([0-9]##)M* ]]; then
        btn=$match[1]; mx=$match[2]; my=$match[3]
        if (( btn == 0 && mx <= 31 && my <= 6 )); then                   # poked the frog
          if [[ -z $phase ]]; then
            (( annoy++ )); last_click=$tick
            (( annoy >= 12 )) && { phase=bye; phase_t=$tick; }
          fi
        elif (( btn == 0 && mx >= 32 )) && (( my >= 1 && my <= ${#rowpane} )) && [[ -n ${rowpane[$my]} ]] && own_pane "${rowpane[$my]}"; then
          focus_pane "${rowpane[$my]}"                                  # left-click a session → jump to its pane
        fi
      elif [[ $buf == " " ]]; then                                         # space → new useless fact
        fetch_fact
      else                                                                 # frog tricks on demand
        [[ -n $phase ]] || case $buf in
          f) start_ev fly 30; flx=$(( RANDOM % 8 + 1 )); fly=$(( RANDOM % 2 + 2 )) ;;
          w) start_ev wink 9 ;;   g) start_ev googly 12 ;;  l) start_ev look 10 ;;
          r) start_ev roll 14 ;;  t) start_ev tongue 12 ;;  y) start_ev yay 20 ;;
          x) start_ev dead 32 ;;  d) start_ev dizzy 20 ;;   z) start_ev nap 40 ;;
        esac
      fi
    fi
  else
    sleep 0.18
  fi
  (( tick++ ))
done

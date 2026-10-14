#!/usr/bin/env zsh
# claude-companion — live animated terminal pet that watches your Claude Code
# sessions. Sessions are discovered from WezTerm panes running `claude`, and
# enriched by each session's hook (companion-event.sh → sessions/<id>) with
# what it is doing. The frog's mood follows the most urgent session.
# Click a session row to focus its pane. Space → new useless fact. Letter keys
# make the pet do tricks (its keys are in the footer). Ctrl+C quits.
emulate -L zsh
setopt extendedglob
zmodload zsh/datetime 2>/dev/null
zmodload -F zsh/stat b:zstat 2>/dev/null
HERE=${0:A:h}                       # pets/ lives next to this script (symlinks resolved)
STATE=${FROK_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/frok}/companion
SDIR="$STATE/sessions"              # written by companion-event.sh
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
  clicked=$1; clicked_at=$EPOCHSECONDS; focused=$1
  if [[ $BACKEND == generic ]]; then     # Windows Terminal: panes frok's layout opened know their id
    [[ -n ${wtpane[$1]} ]] && (( $+commands[wt.exe] )) && wt.exe -w 0 focus-pane -t ${wtpane[$1]} >/dev/null 2>&1 &!
    return
  fi
  if [[ $BACKEND == kitty ]]; then $KT @ focus-window --match "id:${1#k}" >/dev/null 2>&1 &!
  else $WZ cli activate-pane --pane-id "$1" >/dev/null 2>&1 &!; fi
}
US=$'\x1f'; TAB=$'\t'

# Colours come from the terminal's own ANSI palette, so the companion follows
# whatever scheme WezTerm uses (currently Tokyo Night).
G=$'\e[32m'; L=$'\e[34m'; D=$'\e[90m'; W=$'\e[39m'
Y=$'\e[33m'; C=$'\e[36m'; R=$'\e[31m'; M=$'\e[35m'; X=$'\e[0m'

# ── the pet: art, faces and tricks (pets/<name>.zsh, see pets/README.md) ──
PET=${FROK_PET:-frok}; [[ -r $HERE/pets/$PET.zsh ]] || PET=frok
PET_ALT=(); PET_IDLE=(); unfunction pet_trick pet_start pet_frame 2>/dev/null
source $HERE/pets/$PET.zsh
typeset -A trickkey trickframes
for t in $PET_TRICKS; do trickkey[${t%%:*}]=${${t#*:}%%:*}; trickframes[${${t#*:}%%:*}]=${t##*:}; done

# Pane shortcuts for the footer, as frok set them up for this terminal
# ("key=label;key=label…" in generated/keys.txt).
# Footer rows: a same-width label chip on the left, then the row. Chip colours
# come from the frok theme (FROK_UI: hover border accent fg muted), else ANSI.
hexbg() { local c=${1#\#}; print -rn -- $'\e[48;2;'"$((0x${c:0:2}));$((0x${c:2:2}));$((0x${c:4:2}))m"; }
hexfg() { local c=${1#\#}; print -rn -- $'\e[38;2;'"$((0x${c:0:2}));$((0x${c:2:2}));$((0x${c:4:2}))m"; }
ui=(${=FROK_UI:-})
if (( $#ui == 5 )); then
  KB="$(hexbg $ui[1])$(hexfg $ui[4])"; LB="$(hexbg $ui[2])$(hexfg $ui[3])"$'\e[1m'; ACC="$(hexfg $ui[3])"; FB="$(hexfg $ui[2])"
else
  KB=$'\e[100m\e[39m'; LB=$'\e[44m\e[30m\e[1m'; ACC=$L; FB=$'\e[34m'
fi
LW=10                                   # label chip (9) + a space
label() { print -rn -- "${LB} ${(r:7:)1} ${X} "; }
indent=${(l:LW:)}
# section <label> <line>… → label on the first line, the rest indented under it
section() { local n=$1; shift; out+=("$(label $n)$1"); shift; for l; do out+=("$indent$l"); done; }

KEYSFILE=${FROK_GEN:-$HOME/.config/frok/generated}/keys.txt
keyitems=(",${TAB}settings")                     # frok's own: opens the menu
[[ -r $KEYSFILE ]] && for kv in ${(s:;:)"$(<$KEYSFILE)"}; do keyitems+=("${kv%%=*}$TAB${kv#*=}"); done
trickitems=(); for t in $PET_TRICKS; do trickitems+=("${t%%:*}$TAB${${t#*:}%%:*}"); done
# pack <width> <"key<TAB>label">… → packed=(lines): key chips + labels, wrapped between items
pack() {
  local w=$1 it k l cur="" vis=0 n; shift; packed=(); packpos=()
  for it; do
    k=${it%%$TAB*}; l=${it#*$TAB}; (( n = ${#k} + 3 + ${#l} ))
    (( vis > 0 && vis + 3 + n > w )) && { packed+=("$cur"); cur=""; vis=0; }
    (( vis > 0 )) && { cur+="   "; (( vis += 3 )); }
    packpos+=("$(( ${#packed} + 1 )):$(( vis + 1 )):$(( vis + n )):$k")
    cur+="${KB} ${k} ${X} ${D}${l}${X}"; (( vis += n ))
  done
  [[ -n $cur ]] && packed+=("$cur")
}

# 10-cell bar for a percentage: green, yellow from 50, red from 80
bar() {
  local p=$1 f c; (( f = (p + 5) / 10, f > 10 && (f = 10), f < 0 && (f = 0) ))
  (( p < 50 )) && c=$G || { (( p < 80 )) && c=$Y || c=$R; }
  print -rn -- "${c}${(l:$f::━:)}${X}${D}${(l:$((10 - f))::━:)} ${(l:3:)p}%${X}"
}
human() {
  local n=${1:-0}
  if   (( n >= 1000000000 )); then printf '%.1fB' $(( n / 1e9 ))
  elif (( n >= 1000000 ));    then printf '%.1fM' $(( n / 1e6 ))
  elif (( n >= 10000 ));      then printf '%.1fk' $(( n / 1e3 ))
  else print -rn -- $n; fi
}
dur() { local s=$1; (( s < 0 )) && s=0
  if (( s >= 86400 )); then print -rn -- "$((s/86400))d$(( s%86400/3600 ))h"
  elif (( s >= 3600 )); then print -rn -- "$((s/3600))h$(( s%3600/60 ))m"
  else print -rn -- "$((s/60))m"; fi; }

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

# click_button <x> <"fs:fe/cs:ce/pane"> — focus, or close (asks once: "sure?")
click_button() {
  local x=$1 f c pane; f=${${2}%%/*}; c=${${2#*/}%%/*}; pane=${2##*/}
  if [[ -n $f ]] && (( x >= ${f%%:*} && x <= ${f##*:} )); then focus_pane $pane; return 0; fi
  if [[ -n $c ]] && (( x >= ${c%%:*} && x <= ${c##*:} )); then
    if [[ $confirm == $pane ]]; then
      [[ ${panepid[$pane]} == <-> ]] && kill -TERM ${panepid[$pane]} 2>/dev/null   # ends Claude; the pane keeps its shell
      confirm=""
    else confirm=$pane; confirm_until=$(( tick + 15 )); fi
    return 0
  fi
  return 1
}

# ── useless facts (fetched in the background, one in flight at a time) ──
FACTFILE="${TMPDIR:-/tmp}/claude-companion-fact.$$"
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
fetch_fact

# hide cursor + SGR mouse reporting (clicks arrive as \e[<b;x;yM). Echo stays
# off for the whole run, otherwise mouse/scroll reports that land between reads
# get printed onto the screen (e.g. "[[<64;70;5M" when scrolling).
STTY_SAVED=$(stty -g 2>/dev/null)
[[ -t 0 ]] && stty -echo -icanon 2>/dev/null
cleanup() { print -n $'\e[?1000l\e[?1006l\e[?25h\e[?7h\e[?1049l'"$X"; [[ -n $STTY_SAVED ]] && stty "$STTY_SAVED" 2>/dev/null; rm -f "$FACTFILE" "$FACTLOCK" 2>/dev/null; exit 0 }
trap cleanup INT TERM
# settings: the companion steps aside for frok's menu, then starts over (a new
# pet, theme or facts setting takes effect)
open_settings() {
  print -n $'\e[?1000l\e[?1006l\e[?25h\e[?7h\e[?1049l'"$X"
  [[ -n $STTY_SAVED ]] && stty "$STTY_SAVED" 2>/dev/null
  rm -f "$FACTFILE" "$FACTLOCK" 2>/dev/null
  trap '' INT                          # Ctrl+C leaves the menu, not the companion
  ${HERE:h:h}/bin/frok menu
  exec ${HERE:h:h}/bin/frok companion run
}
print -n $'\e[?1049h\e[2J\e[?25l\e[?7l\e[?1000h\e[?1006h'   # alternate screen: no scrollback


typeset -A PRI=(waiting 7 error 6 working 5 dizzy 4 thinking 3 bg 2 done 1 idle 0)
typeset -A COL=(waiting $Y error $R working $C dizzy $M thinking $L bg $C done $G idle $G)
typeset -A LAB=(waiting "needs you" error "error" working "working" dizzy "compacting" thinking "thinking" bg "background" done "done" idle "idle")

ago() { local s=$1; (( s < 60 )) && { print -n "${s}s"; return }; (( s < 3600 )) && { print -n "$((s/60))m"; return }; print -n "$((s/3600))h"; }
cut_to() { local s=$1 n=$2; (( n < 2 )) && n=2; (( ${#s} > n )) && s="${s[1,n-1]}…"; print -rn -- "$s"; }

# ── panes: titles, ttys, and which ones run claude (refreshed every ~2s) ──
typeset -A ptitle claudepane bgcount alive pcwd wtpane
# A companion opened by frok's layout shows only its own launch: the layout's
# panes carry FROK_PANE and all start together, so a session belongs to us when
# its pane started within 30s of ours. (Another tab's sessions stay untouched.)
penv()  { [[ -r /proc/$1/environ ]] && print -r -- ${${(M)${(0)"$(</proc/$1/environ)"}:#FROK_PANE=*}#FROK_PANE=}; }
pstat() { local s; s=$(</proc/$1/stat) 2>/dev/null || return 1; print -r -- ${s##*) }; }   # fields from 3 on
typeset -A lstart
launch_start() {        # start time (clock ticks) of the outermost process carrying FROK_PANE
  local p=$1 top=$1 pp; local -a f
  [[ -n ${lstart[$1]} ]] && { print -r -- ${lstart[$1]}; return; }
  while f=(${=$(pstat $p)}) && pp=${f[2]} && (( pp > 1 )) && [[ -n $(penv $pp) ]]; do top=$pp; p=$pp; done
  f=(${=$(pstat $top)}); lstart[$1]=${f[20]}; print -r -- ${f[20]}
}
MYPANE=""; MYLAUNCH=0; HZ=$(getconf CLK_TCK 2>/dev/null || print 100)
[[ $BACKEND == generic && -n $FROK_PANE && -r /proc/$$/stat ]] && { MYPANE=$FROK_PANE; MYLAUNCH=$(launch_start $$); }
typeset -A mine patime panepid; pg=1; confirm=""; confirm_until=0; typeset -A btns
focused=""; clicked=""; clicked_at=0

refresh_generic() {
  local -a w pslines; local -A cpane; local line ls
  pslines=("${(@f)$(ps -Ao pid=,ppid=,tty=,args= 2>/dev/null)}")
  for line in "${pslines[@]}"; do
    w=(${=line})
    # native `claude`, or npm's `node …/claude-code/cli.js` (common on Linux/WSL)
    [[ ( ${w[4]} == (*/|)claude || ${w[5]} == *claude-code/cli.js ) && ${w[3]} != (\?|\?\?|-) ]] || continue
    claudepane[t:${w[3]}]=1; alive[t:${w[3]}]=1; cpane[${w[1]}]=t:${w[3]}; panepid[t:${w[3]}]=${w[1]}
    # when you last typed in (or focused) the pane: its tty's access time
    local -a at; zstat -A at +atime /dev/${w[3]} 2>/dev/null && patime[t:${w[3]}]=${at[1]}
    # a Windows Terminal pane from frok's layout carries its pane id (FROK_PANE)
    wtpane[t:${w[3]}]=$(penv ${w[1]})
    if [[ -z $MYPANE ]]; then mine[t:${w[3]}]=1
    elif [[ -n ${wtpane[t:${w[3]}]} ]]; then
      ls=$(launch_start ${w[1]}); (( ls - MYLAUNCH < 30 * HZ && MYLAUNCH - ls < 30 * HZ )) && mine[t:${w[3]}]=1
    fi
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
  ptitle=(); claudepane=(); bgcount=(); alive=(); wtpane=(); mine=(); patime=(); panepid=(); focused=""
  if [[ -n ${FROK_DEMO-} ]]; then       # screenshots (docs/screenshots): sessions only from the state files
    local f p; for f in $SDIR/*(N.); do IFS=$US read -r _ _ p _ < $f; [[ -n $p ]] && { alive[$p]=1; wtpane[$p]=demo; panepid[$p]=demo; }; done
    focused=${FROK_DEMO_FOCUS-}; return
  fi
  if [[ $BACKEND == generic ]]; then
    refresh_generic
    # Windows Terminal can't tell us which pane has focus: take the one you
    # last typed in, or the one you just jumped to from here
    local p best=0
    for p in ${(k)patime}; do [[ -n $MYPANE && -z ${mine[$p]} ]] && continue; (( patime[$p] > best )) && { best=${patime[$p]}; focused=$p; }; done
    [[ -n $clicked ]] && (( clicked_at >= best )) && focused=$clicked
    return
  fi
  if [[ $BACKEND == kitty ]]; then
    local kl kid kc kt
    for kl in "${(@f)$($KT @ ls 2>/dev/null | jq -r '.[].tabs[].windows[] |
        "k\(.id)\t\([.foreground_processes[]?.cmdline[0]? // "" | split("/") | last] | index("claude") != null)\t\(.title)"' 2>/dev/null)}"; do
      [[ -z "$kl" ]] && continue
      kid=${kl%%$TAB*}; kl=${kl#*$TAB}; kc=${kl%%$TAB*}; kt=${kl#*$TAB}
      ptitle[$kid]=$kt; alive[$kid]=1; [[ $kc == true ]] && claudepane[$kid]=1
    done
    focused=k$($KT @ ls 2>/dev/null | jq -r '[.[] | select(.is_focused) | .tabs[] | select(.is_focused) | .windows[] | select(.is_focused) | .id][0] // empty' 2>/dev/null)
    return
  fi
  local -A ttypane; local line id tty title
  for line in "${(@f)$($WZ cli list --format json 2>/dev/null | jq -r '.[] | "\(.pane_id)\t\(.tty_name)\t\(.title)"' 2>/dev/null)}"; do
    [[ -z "$line" ]] && continue
    id=${line%%$TAB*}; line=${line#*$TAB}; tty=${${line%%$TAB*}#/dev/}; title=${line#*$TAB}
    ptitle[$id]=$title; alive[$id]=1; ttypane[$tty]=$id
  done
  focused=$($WZ cli list-clients --format json 2>/dev/null | jq -r '.[0].focused_pane_id // empty' 2>/dev/null)
  # claude processes per pane, and the shells they're running: a finished turn
  # that still has shell children is running background tasks
  local -a w; local -A cpane
  local -a pslines; pslines=("${(@f)$(ps -Ao pid=,ppid=,tty=,comm= 2>/dev/null)}")
  for line in "${pslines[@]}"; do
    w=(${=line})
    [[ ${w[4]} == (*/|)claude && -n ${ttypane[${w[3]}]} ]] || continue
    claudepane[${ttypane[${w[3]}]}]=1; cpane[${w[1]}]=${ttypane[${w[3]}]}; panepid[${ttypane[${w[3]}]}]=${w[1]}
  done
  for line in "${pslines[@]}"; do
    w=(${=line})
    [[ -n ${cpane[${w[2]}]} && ${w[4]} == (*/|)(zsh|bash|sh) ]] && (( bgcount[${cpane[${w[2]}]}]++ ))
  done
}

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


# ── pet animation ─────────────────────────────────────────────────────
# The pet's face follows the most urgent session; state changes trigger short
# reactions (error → x_x + shiver, done → yay, needs you → alert) and, when
# nothing's happening, it does random tricks. Everything stays in fixed cells.
typeset -A oldst
ev=""; ev_until=0; quiet=0
annoy=0; last_click=0; phase=""; phase_t=0   # clicks on the pet annoy it
start_ev() { ev=$1; ev_until=$(( tick + $2 )); (( $+functions[pet_start] )) && pet_start $1; }
start_trick() { start_ev $1 ${trickframes[$1]:-12}; }
spin=('|' '/' '-' '\'); qs=('?' '..' '...'); dz=('@' 'o' 'O' 'o')

build_frog() {
  local o=$PET_EYE e1=$PET_EYE e2=$PET_EYE mouth=${PET_MOUTH[rest]} bub="" bc=$Y shx=0 off=0 fc=$ec left
  local alt=0 dy=0 hide=0
  local -a marg mc; marg=("" "" ""); mc=($Y $W $W)
  (( tick >= ev_until )) && ev=""
  if [[ -z $ev && -z $phase && ( $top == idle || $top == done || $top == bg ) ]] && (( annoy == 0 && quiet <= 600 && $#PET_IDLE && RANDOM % 110 == 0 )); then
    start_trick ${PET_IDLE[RANDOM % $#PET_IDLE + 1]}
  fi
  (( $+functions[pet_frame] )) && pet_frame
  # base expression from the most urgent session
  case $top in
    working)  e1='>'; e2='<'; (( (tick/2) % 2 )) && mouth=${PET_MOUTH[talk]}; bub=${spin[tick % 4 + 1]} ;;
    thinking) (( (tick/6) % 2 )) && { e1='.'; e2='.'; }; bub=${qs[(tick/3) % 3 + 1]} ;;
    waiting)  e1='O'; e2='O'; mouth=${PET_MOUTH[open]}; (( (tick/3) % 2 )) && bub='!' ;;
    error)    e1='x'; e2='x'; mouth=${PET_MOUTH[sad]}; bub='x_x'; bc=$R ;;
    dizzy)    e1=${dz[tick % 4 + 1]}; e2=${dz[(tick + 2) % 4 + 1]}; bub='~' ;;
    done)     e1='^'; e2='^'; mouth=${PET_MOUTH[happy]} ;;
    bg)       bub=${qs[(tick/4) % 3 + 1]} ;;
  esac
  # dozing off after 10 quiet minutes
  if [[ $top == idle ]] && (( quiet > 600 )) && [[ -z $ev ]]; then
    e1='-'; e2='-'; bub=""
    local zr=$(( 3 - (tick / 5) % 3 )); marg[$zr]="${(l:$((7 - zr)):)}${${:-z Z z}[$(( (tick / 5) % 3 * 2 + 1 ))]}"; mc[$zr]=$D
  fi
  # short reactions and tricks override the base face: the pet's own first
  left=$(( ev_until - tick ))
  if [[ -n $ev ]] && ! { (( $+functions[pet_trick] )) && pet_trick $ev; }; then
    case $ev in
      dead)   e1='x'; e2='x'; mouth=${PET_MOUTH[sad]}; bub='x_x'; bc=$R; (( left > 18 && tick % 2 )) && shx=1 ;;
      yay)    e1='^'; e2='^'; mouth=${PET_MOUTH[happy]}; (( (tick/2) % 2 )) && bub='yay!' || bub='\o/'
              marg[2]="${(l:$(( RANDOM % 6 + 1 )):)}*"; mc[2]=$Y; marg[3]="${(l:$(( RANDOM % 7 + 1 )):)}+"; mc[3]=$Y ;;
      alert)  e1='O'; e2='O'; mouth=${PET_MOUTH[open]}; bub='!!' ;;
      wink)   e1='-' ;;
      googly) e1='O'; e2='.' ;;
      look)   (( left > 4 )) && { e1='.'; e2=$o; } || { e1=$o; e2='.'; } ;;
      roll)   local rl=("$o" '.' ',' '.'); e1=${rl[left % 4 + 1]}; e2=$e1 ;;
      tongue) mouth=${PET_MOUTH[tongue]}; bub=':P' ;;
      dizzy)  e1=${dz[tick % 4 + 1]}; e2=${dz[(tick + 2) % 4 + 1]}; bub='~@~' ;;
      nap)    e1='-'; e2='-'; bub=""
              local nr=$(( 3 - (tick / 4) % 3 )); marg[$nr]="${(l:$((7 - nr)):)}${${:-z Z z}[$(( (tick / 4) % 3 * 2 + 1 ))]}"; mc[$nr]=$D ;;
    esac
  fi
  # ── annoyance (clicks on the pet), overrides everything ──────────────
  (( annoy > 0 && tick - last_click > 15 && tick % 15 == 0 )) && (( annoy-- ))
  if [[ -z $phase ]] && (( annoy > 0 )); then
    if   (( annoy <= 2 )); then e1=$o; e2='-'; bub='hey!'
    elif (( annoy <= 4 )); then e1='='; e2='='; mouth=${PET_MOUTH[rest]}; bub='stop it'
    elif (( annoy <= 6 )); then e1='\'; e2='/'; mouth=${PET_MOUTH[grit]}; bub='grr'; bc=$R; fc=$R; (( tick % 2 )) && shx=1
    elif (( annoy <= 9 )); then e1='\'; e2='/'; mouth=${PET_MOUTH[angry]}; (( (tick/2) % 2 )) && bub='GRRR' || bub='!!!'
                               bc=$R; (( tick % 2 )) && fc=$R || fc=$Y; shx=$(( RANDOM % 3 ))
    else                        e1='@'; e2='@'; mouth=${PET_MOUTH[angry]}; bub='ENOUGH'; bc=$R; fc=$R; shx=$(( RANDOM % 4 )); fi
  fi
  if [[ -n $phase ]]; then
    local pt=$(( tick - phase_t ))
    case $phase in
      bye)   e1='-'; e2='-'; mouth=${PET_MOUTH[rest]}; bub='bye.'; bc=$D; fc=$ec
             (( pt >= 10 )) && { phase=leave; phase_t=$tick; } ;;
      leave) off=$(( pt * 2 )); (( off >= 31 )) && { off=31; phase=gone; phase_t=$tick; } ;;
      gone)  off=31; (( pt >= 125 )) && { phase=back; phase_t=$tick; } ;;
      back)  off=$(( 31 - pt * 2 )); (( off <= 0 )) && { off=0; phase=hmph; phase_t=$tick; } ;;
      hmph)  e1='-'; e2=$o; bub='hmph.'; bc=$D; (( pt >= 25 )) && { phase=""; annoy=0; } ;;
    esac
  fi

  # occasional blink when calm
  [[ -z $ev && -z $phase && annoy -eq 0 && ( $top == idle || $top == bg ) && $e1 == $o ]] && (( blink )) && { e1='-'; e2='-'; }
  [[ -n $bub ]] && { marg[1]="${(l:8:)bub}"; mc[1]=$bc; }

  # the art with this frame's eyes and mouth, maybe its second frame, bobbing by dy
  local -a src art; local i l
  (( alt && $#PET_ALT )) && src=("${PET_ALT[@]}") || src=("${PET_ART[@]}")
  for (( i = 1; i <= 6; i++ )); do
    l=${src[i - dy]}; (( i - dy < 1 )) && l=""
    (( hide )) && l=""
    art[i]=${${${l//\{1\}/$e1}//\{2\}/$e2}//\{m\}/$mouth}
  done
  local sp="${(l:shx:)}"
  frogrow=()
  if (( off > 0 )); then                         # sliding away / back in, or gone
    for i in {1..6}; do frogrow[$i]="${fc}${(r:31:)${art[$i][off+1,-1]}}${X}"; done
    if [[ $phase == gone ]]; then
      frogrow[3]="${D}${(r:31:):-       $PET_GONE}${X}"
      frogrow[6]="${D}${(r:31:):-  .   .   .   .}${X}"
    fi
    return
  fi
  # rows 1-3: bubbles and props in the first 9 columns, then the art
  for i in 1 2 3; do frogrow[$i]="${mc[$i]}${(r:9:)marg[$i]}${X}${fc}${(r:22:)${:-$sp${art[$i][10,-1]}}}${X}"; done
  for i in 4 5 6; do frogrow[$i]="${fc}${(r:31:)${:-$sp${art[$i]}}}${X}"; done
}

typeset -a prev frogrow; tick=0; lastfact=""
update_size; refresh_panes; refresh_sessions
while true; do
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

  if [[ -t 0 ]]; then
    if read -t 0.18 -k 1 -s key 2>/dev/null; then
      buf=$key
      while read -t 0.01 -k 1 -s key 2>/dev/null; do buf+=$key; done   # rest of a multi-byte key / mouse report
      if [[ $buf == $'\e[<'(#b)([0-9]##)';'([0-9]##)';'([0-9]##)M* ]]; then
        btn=$match[1]; mx=$match[2]; my=$match[3]
        if (( btn == 0 && mx >= 2 && mx <= 32 && my >= 2 && my <= 7 )); then   # poked the frog
          if [[ -z $phase ]]; then
            (( annoy++ )); last_click=$tick
            (( annoy >= 12 )) && { phase=bye; phase_t=$tick; }
          fi
        elif (( btn == 0 )) && (( (ri = my - sess_off) >= 1 )) && [[ -n ${btns[$ri]} ]] && click_button $mx "${btns[$ri]}"; then
          :                                                             # a session's focus / ✕ button
        elif (( btn == 0 )) && [[ -n $pager ]] && (( my - sess_off == ${pager%%/*} )); then
          pp=(${(s:/:)pager})                                           # ‹ prev / next ›
          (( mx >= ${pp[2]%%:*} && mx <= ${pp[2]##*:} && pg > 1 )) && (( pg-- ))
          (( mx >= ${pp[3]%%:*} && mx <= ${pp[3]##*:} && pg < npg )) && (( pg++ ))
        elif (( btn == 0 && ( stacked || mx >= 36 ) )) && (( (ri = my - sess_off) >= 1 && ri <= ${#rowpane} )) && [[ -n ${rowpane[$ri]} ]] && own_pane "${rowpane[$ri]}"; then
          focus_pane "${rowpane[$ri]}"                                  # left-click a session → jump to its pane
        elif (( btn == 0 && my == keysrow )) && [[ ${keypos[1]} == 1:* ]] && (( mx >= LW + ${${(s.:.)keypos[1]}[2]} && mx <= LW + ${${(s.:.)keypos[1]}[3]} )); then
          open_settings                                                 # the settings button
        elif (( btn == 0 && my >= tricksrow && my < tricksrow + ${#tricklines} )); then   # click a trick
          for tp in $trickpos; do
            tq=(${(s.:.)tp})
            (( my == tricksrow + tq[1] - 1 && mx >= LW + tq[2] && mx <= LW + tq[3] )) && [[ -z $phase ]] && start_trick ${trickkey[${tq[4]}]}
          done
        elif (( btn == 0 && my == statsrow )); then                     # click a period tab
          for (( k = 1; k <= 3; k++ )); do
            (( mx >= ${tabx[k]%%:*} && mx <= ${tabx[k]##*:} )) && pi=$k
          done
        fi
      elif [[ $buf == , ]]; then                                           # , → settings
        open_settings
      elif [[ $buf == p ]]; then                                           # p → next period
        (( pi = pi % 3 + 1 ))
      elif [[ $buf == '[' ]]; then (( pg > 1 )) && (( pg-- ))              # [ / ] → session pages
      elif [[ $buf == ']' ]]; then (( pg < npg )) && (( pg++ ))
      elif [[ $buf == " " ]]; then                                         # space → new useless fact
        fetch_fact
      elif [[ -n ${trickkey[$buf]} && -z $phase ]]; then                    # the pet's tricks on demand
        start_trick ${trickkey[$buf]}
      fi
    fi
  else
    sleep 0.18
  fi
  (( tick++ ))
done

# panes.zsh — the terminal side: which terminal we are in, its panes and which
# run Claude, focusing one, and the size of our own pane.

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

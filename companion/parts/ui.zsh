# ui.zsh — drawing helpers: label and key chips, bars, number formats, and
# what each session state looks like.

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

typeset -A PRI=(waiting 7 error 6 working 5 dizzy 4 thinking 3 bg 2 done 1 idle 0)
typeset -A COL=(waiting $Y error $R working $C dizzy $M thinking $L bg $C done $G idle $G)
typeset -A LAB=(waiting "needs you" error "error" working "working" dizzy "compacting" thinking "thinking" bg "background" done "done" idle "idle")

ago() { local s=$1; (( s < 60 )) && { print -n "${s}s"; return }; (( s < 3600 )) && { print -n "$((s/60))m"; return }; print -n "$((s/3600))h"; }
cut_to() { local s=$1 n=$2; (( n < 2 )) && n=2; (( ${#s} > n )) && s="${s[1,n-1]}…"; print -rn -- "$s"; }

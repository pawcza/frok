# widgets.zsh — the dashboard below the sessions: a list of widgets you pick
# and order (frok.json: "dashboard", options under "widgets.<name>").
#
# A widget is widgets/<name>.zsh (see widgets/README.md). Every frame the
# engine asks each enabled widget to fill `wl` (its lines, for width $cw) and
# draws them under a label chip; clicks and keys go back to the widget.

CFG=${FROK_CFG:-${FROK_CONFIG_DIR:-$HOME/.config/frok}/frok.json}
WSTATE=$STATE/widgets; mkdir -p $WSTATE
DASHBOARD_DEFAULT=(fact stats limits keys tricks)
typeset -A W_LABEL W_KEYS WOPT
for f in $HERE/widgets/*.zsh(N); do source $f; done

dashboard=(); cfg_mtime=""
# dashboard_load — the widget list and options, again whenever frok.json changes
dashboard_load() {
  local -a m; zstat -A m +mtime -- $CFG 2>/dev/null
  [[ ${m[1]-} == $cfg_mtime && ${#dashboard} -gt 0 ]] && return
  cfg_mtime=${m[1]-}
  local list; list=$(jq -r '.dashboard // empty | .[]' $CFG 2>/dev/null)
  dashboard=(${(f)list}); (( $#dashboard )) || dashboard=($DASHBOARD_DEFAULT)
  dashboard=(${dashboard:#none})
  local k v; WOPT=()
  while IFS=$TAB read -r k v; do [[ -n $k ]] && WOPT[$k]=$v; done < <(jq -r '
    .widgets // {} | to_entries[] | .key as $w | .value | to_entries[] | "\($w).\(.key)\t\(.value)"' $CFG 2>/dev/null)
  local w; for w in $dashboard; do (( $+functions[w_${w}_init] )) && w_${w}_init; done
}
# wopt <widget> <option> <default>
wopt() { print -r -- ${WOPT[$1.$2]:-$3}; }

# draw_widgets — every enabled widget into `out`; clickable spots into `wclicks`
# as "row:x0:x1:widget:action" (row within out, x on screen)
draw_widgets() {
  local w l i c; wclicks=()
  for w in $dashboard; do
    (( $+functions[w_${w}_render] )) || continue
    wl=(); wclick=()
    w_${w}_render
    (( $#wl )) || continue
    local start=$(( ${#out} + 1 ))
    section ${W_LABEL[$w]:-$w} "${wl[@]}"
    for c in $wclick; do        # "line:x0:x1:action", x counted from the start of the content
      local -a p=("${(@s.:.)c}")
      wclicks+=("$(( start + p[1] - 1 )):$(( LW + p[2] )):$(( LW + p[3] )):$w:${(j.:.)p[4,-1]}")
    done
  done
}

# refresh_widgets — each widget's own refresh, if it has one (it decides how often)
refresh_widgets() { local w; for w in $dashboard; do (( $+functions[w_${w}_refresh] )) && w_${w}_refresh; done; }

# widget_click <screen row> <x> → true if a widget took it
widget_click() {
  local c; local -a p
  for c in $wclicks; do
    p=("${(@s.:.)c}")
    (( $1 == p[1] + wrow_off && $2 >= p[2] && $2 <= p[3] )) || continue
    w_${p[4]}_click "${(j.:.)p[5,-1]}"; return 0
  done
  return 1
}
# widget_key <key> → true if an enabled widget took it
widget_key() {
  local w=${W_KEYS[$1]-}
  [[ -n $w && ${dashboard[(Ie)$w]} -gt 0 ]] && (( $+functions[w_${w}_key] )) || return 1
  w_${w}_key $1
}

# a line of text from the internet, made safe to print: no control characters
# (a feed can't move the cursor or recolour the terminal)
clean() { print -rn -- ${1//[[:cntrl:]]/}; }

# open_url <url> — in the browser, http(s) only
open_url() {
  [[ $1 == http(s|)://* ]] || return
  if [[ -n ${WSL_DISTRO_NAME-} ]]; then
    if (( $+commands[wslview] )); then wslview "$1"
    else powershell.exe -NoProfile -Command "Start-Process '${1//\'/\'\'}'"; fi
  elif (( $+commands[open] )) && [[ $OSTYPE == darwin* ]]; then open "$1"
  else xdg-open "$1"; fi >/dev/null 2>&1 &!
}

# notify <title> <text> — a desktop notification where we can make one
notify() {
  {
    if [[ -n ${WSL_DISTRO_NAME-} ]]; then
      powershell.exe -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; \$n = New-Object System.Windows.Forms.NotifyIcon;
        \$n.Icon = [System.Drawing.SystemIcons]::Information; \$n.Visible = \$true;
        \$n.ShowBalloonTip(8000, '${1//\'/\'\'}', '${2//\'/\'\'}', 'Info'); Start-Sleep 9; \$n.Dispose()"
    elif [[ $OSTYPE == darwin* ]]; then osascript -e "display notification \"${2//\"/}\" with title \"${1//\"/}\""
    elif (( $+commands[notify-send] )); then notify-send "$1" "$2"; fi
  } >/dev/null 2>&1 &!
}

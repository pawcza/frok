# dashboard.zsh — which widgets the companion shows, in what order, and their
# options (frok.json: "dashboard" and "widgets.<name>.<option>"). Running
# companions pick changes up within a second.

WIDGET_DIR=$FROK_HOME/companion/widgets
widget_names() { local f; for f in $WIDGET_DIR/*.zsh(N); do print ${f:t:r}; done; }
# widget_about <name> — the line under its name: what it shows, then its options
widget_about() { sed -n '1s/^# [a-z]* — //p' $WIDGET_DIR/$1.zsh; }
widget_options() { sed -n 's/^# options: //p' $WIDGET_DIR/$1.zsh; }

dashboard_list() { cfg '.dashboard[]'; }
dashboard_save() { cfg_set .dashboard "$(print -rl -- "$@" | jq -R . | jq -sc .)"; }

dashboard_cmd() {
  cfg_init
  local -a cur=(${(f)"$(dashboard_list)"}); local w=${2-}
  [[ -n $w && $1 != (|reset) ]] && { [[ -f $WIDGET_DIR/$w.zsh ]] || die "no widget '$w' (try: frok dashboard)"; }
  case ${1-} in
    "")
      local i=1 n
      print "dashboard, top to bottom:"
      for n in $cur; do printf '  %d  %-8s %s\n' $(( i++ )) $n "$(widget_about $n)"; done
      print "\nmore widgets:"
      for n in $(widget_names); do (( ${cur[(Ie)$n]} )) || printf '     %-8s %s\n' $n "$(widget_about $n)"; done
      print "\nfrok dashboard add|remove <widget> · move <widget> <position> · set <widget> <option> <value> · reset" ;;
    add)
      (( ${cur[(Ie)$w]} )) && { say "$w is already on the dashboard"; return }
      local at=${3:-$(( $#cur + 1 ))}; cur[$at,0]=($w)
      dashboard_save $cur; say "added $w" ;;
    remove)
      dashboard_save ${cur:#$w}; say "removed $w" ;;
    move)
      [[ ${3-} == <-> ]] || die "move <widget> <position, 1 is the top>"
      cur=(${cur:#$w}); cur[$3,0]=($w); dashboard_save $cur; say "$w is now number $3" ;;
    set)
      [[ -n ${3-} ]] || die "set <widget> <option> <value> (an empty value removes it)"
      if [[ -z ${4-} ]]; then cfg_set ".widgets.$w" "$(cfg ".widgets.$w // {} | del(.\"$3\")" | jq -c . 2>/dev/null || print '{}')"
      else cfg_set ".widgets.$w.\"$3\"" "$(jstr $4)"; fi
      say "$w: $3 = ${4:-(default)}" ;;
    reset)
      cfg_set .dashboard "$(jq -c .dashboard <<< $FROK_DEFAULTS)"; say "dashboard back to the defaults" ;;
    *) die "frok dashboard [add|remove|move|set|reset]" ;;
  esac
}

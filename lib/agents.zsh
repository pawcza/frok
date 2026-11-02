# agents.zsh: coding agents: which are here, how they report to the companion,
# and what you run in agent panes. frok is complete without any of them.
#
# Each agent that can report its state is one file, lib/agents/<id>.zsh, with
#   agent_<id>_present            is it installed?
#   agent_<id>_connect on|off     add or remove its reporting (only touches frok's own entries)
#   agent_<id>_connected          is its reporting in place?
#   agent_<id>_command            how you start it
#   AGENT_FEATURES[<id>]          what the companion gets from it
# The rest (Antigravity, anything `frok agents watch` names) is found by process.

source $FROK_HOME/companion/agents/agents.sh
AGENTS=(claude codex gemini opencode aider)
typeset -A AGENT_FEATURES
for f in $AGENTS; do source $FROK_HOME/lib/agents/$f.zsh; done

agent_present()   { agent_${1}_present; }
agent_connected() { agent_${1}_connected; }
agents_installed() { local a; for a in $AGENTS; do agent_present $a && print $a; done; }

# Report-only entries in a JSON settings file, the shape Claude Code, Codex and
# Gemini CLI share: { "hooks": { "<event>": [ { "hooks": [ {command…} ] } ] } }.
AGENT_HOOKS_JQ='
  def ours: (.command // "") | test("companion-event\\.sh( |$)");
  def drop_ours: .hooks = ((.hooks // {}) | with_entries(.value |= (map(.hooks |= map(select(ours | not))) | map(select((.hooks | length) > 0))))
                                          | with_entries(select((.value | length) > 0)));
  def add_ours($evs; $entry): reduce $evs[] as $e (.; .hooks[$e] = ((.hooks[$e] // []) + [$entry]));
  def tidy: if .hooks == {} then del(.hooks) else . end;'

# json_edit <file> <jq args…>: change a settings file, backed up, only if the
# result differs. A file jq can't read (a settings file with comments, say) is
# left alone with a warning. True when it changed.
json_edit() {
  local f=$1 changed; shift
  changed=$(jq "$@" $f 2>/dev/null) || { warn "couldn't read ${f/#$HOME/~} as JSON, left it alone"; return 1 }
  [[ $changed == "$(jq . $f)" ]] && return 1
  cp $f $f.bak.frok
  print -r -- $changed >| $f
  say "companion hooks → ${f/#$HOME/~}"
}

# A hook command that's safe for the shell the agent runs it in.
agent_hook_cmd() { print -r -- "${(q)COMPANION_DIR}/companion-event.sh $1"; }
# hooks_present <file>: our command is in it, and the script it names exists
hooks_present() {
  local -a c=(${(f)"$(jq -r '[.hooks[]?[]?.hooks[]?.command // empty | select(test("companion-event\\.sh( |$)"))] | unique | .[]' $1 2>/dev/null)"})
  (( $#c == 1 )) && [[ -x ${(Q)${(z)c[1]}[1]} ]]
}

agents_disabled() { cfg '.agents_off[]?'; }
agent_disabled()  { local -a l=(${(f)"$(agents_disabled)"}); (( ${l[(Ie)$1]} )); }
agents_allowed()  { cfg '.agents_on[]?'; }
agent_allowed()   { local -a l=(${(f)"$(agents_allowed)"}); (( ${l[(Ie)$1]} )); }

# agent_decide <agent> on|off: remember your answer for that agent
agent_decide() {
  local add=.agents_on del=.agents_off
  [[ $2 == off ]] && { add=.agents_off; del=.agents_on }
  cfg_set $add "$(jq -c --arg a $1 "($add // []) + [\$a] | unique" $FROK_CFG)"
  cfg_set $del "$(jq -c --arg a $1 "($del // []) - [\$a]" $FROK_CFG)"
}

# agents_ask [--yes]: an agent's settings are its own, so frok asks once before
# touching them and remembers the answer. Agents already connected stay connected.
# With no terminal to ask in, nothing changes and you're told how to connect.
agents_ask() {
  local a yes=${1-} q
  local -a waiting=()
  [[ $(cfg .companion) == none ]] && return 0
  for a in $AGENTS; do
    agent_present $a || continue
    agent_disabled $a || agent_allowed $a && continue
    if agent_connected $a || [[ $yes == --yes ]]; then agent_decide $a on; continue; fi
    agent_label $a
    if [[ ! -t 0 || ! -t 1 ]]; then waiting+=($a); continue; fi
    q="  Connect $AGENT_LABEL to the companion? frok adds its own entries to that agent's settings. [y/N] "
    if read -q "?$q"; then agent_decide $a on; else agent_decide $a off; fi
    print
  done
  (( $#waiting )) && say "found ${(j:, :)waiting}: connect with \`frok agents on <agent>\` or \`frok apply --yes\`"
  return 0
}

# agents_connect <pet|none>: agents you said yes to report to the companion, and
# nothing else is touched. With no companion, none of them do.
agents_connect() {
  local a
  for a in $AGENTS; do
    if [[ $1 == none ]] || agent_disabled $a; then agent_${a}_connect off
    elif agent_present $a && agent_allowed $a; then agent_${a}_connect on; fi
  done
}

# What agent panes run: your `frok agent` command. While that's still the
# default and Claude Code isn't here, the first agent that is; with none, a
# shell, so a layout never opens on "command not found".
agent_command() {
  local c=$(cfg .agent)
  if [[ $c == claude ]] && ! has claude; then print -r -- ${${(f)"$(agent_choices)"}[1]-}
  else print -r -- $c; fi
}

# Every way to start an agent here, the likeliest first.
agent_choices() {
  local a
  claude_choices
  for a in $(agents_installed); do [[ $a == claude ]] || agent_${a}_command; done
}

agents_cmd() {
  cfg_init
  case ${1-} in
    "")
      local a state
      for a in $AGENTS; do
        agent_label $a
        if ! agent_present $a; then state="not installed"
        elif agent_disabled $a; then state="off"
        elif agent_connected $a; then state="connected"
        else state="not connected (frok agents on $a)"; fi
        printf '  %-13s %-27s %s\n' $AGENT_LABEL $state ${AGENT_FEATURES[$a]}
      done
      printf '  %-13s %-27s %s\n' Antigravity "$(has agy && print found || print 'not installed')" "shown as running, no status"
      for a in ${(f)"$(cfg '.agents_watch[]?')"}; do printf '  %-13s %-27s %s\n' $a watched "shown as running, no status"; done
      print "\nfrok agents on|off <agent> · watch|unwatch <command>" ;;
    on|off)
      (( ${AGENTS[(Ie)${2-}]} )) || die "frok agents $1 <agent> (one of: $AGENTS)"
      if [[ $1 == off ]]; then
        agent_decide $2 off
        agent_${2}_connect off; say "$2 no longer reports to the companion"
      else
        agent_present $2 || die "$2 isn't installed"
        agent_decide $2 on
        agent_${2}_connect on; say "$2 reports to the companion"
      fi ;;
    watch)
      [[ ${2-} == [A-Za-z0-9._-]## ]] || die "frok agents watch <command name>"
      cfg_set .agents_watch "$(jq -c --arg a $2 '(.agents_watch // []) + [$a] | unique' $FROK_CFG)"
      say "the companion shows any pane running $2 (restart the companion pane)" ;;
    unwatch)
      cfg_set .agents_watch "$(jq -c --arg a ${2-} '(.agents_watch // []) - [$a]' $FROK_CFG)"
      say "stopped watching ${2-}" ;;
    *) die "frok agents [on|off <agent> | watch|unwatch <command>]" ;;
  esac
}

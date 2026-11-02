# aider.zsh: aider's only signal is its notification command, run when a reply
# is finished or a question is waiting. It goes in a marked block in
# ~/.aider.conf.yml, unless you already have notification settings of your own.

AGENT_FEATURES[aider]="reply finished only"
AIDER_BEGIN="# >>> frok companion (\`frok agents off aider\` removes this)"
AIDER_END="# <<< frok companion"

aider_conf() { print -r -- $HOME/.aider.conf.yml; }

agent_aider_present() { has aider; }
agent_aider_command() { print aider; }

aider_strip() { sed "/^$AIDER_BEGIN\$/,/^$AIDER_END\$/d" $1; }

agent_aider_connect() {
  local f=$(aider_conf) cmd=$(agent_hook_cmd aider)
  if [[ $1 == off ]]; then
    agent_aider_connected || { grep -qsF "$AIDER_BEGIN" $f || return 0 }
    local rest; rest=$(aider_strip $f)
    print -r -- $rest >| $f
    [[ -n ${rest//[[:space:]]/} ]] || rm -f $f
    return 0
  fi
  grep -qsF "notifications-command: $cmd" $f && return 0
  if [[ -f $f ]] && aider_strip $f | grep -qE '^notifications(-command|_command)?:'; then
    warn "aider: ~/.aider.conf.yml has its own notification settings, left alone (add: notifications-command: $cmd)"
    return 0
  fi
  local rest=""; [[ -f $f ]] && { cp $f $f.bak.frok; rest=$(aider_strip $f); }
  { [[ -n $rest ]] && print -r -- $rest
    print -r -- $AIDER_BEGIN
    print -r -- "notifications: true"
    print -r -- "notifications-command: $cmd"
    print -r -- $AIDER_END
  } >| $f
  say "companion notifications → ${f/#$HOME/~}"
}

agent_aider_connected() { grep -qsF "notifications-command: $(agent_hook_cmd aider)" $(aider_conf); }

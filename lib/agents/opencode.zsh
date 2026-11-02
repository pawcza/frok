# opencode.zsh: opencode reports through a plugin, one file in its global
# plugins folder, written from companion/agents/opencode-plugin.js.

AGENT_FEATURES[opencode]="status, session titles"

opencode_plugin() { print -r -- ${XDG_CONFIG_HOME:-$HOME/.config}/opencode/plugins/frok-companion.js; }

agent_opencode_present() { has opencode; }
agent_opencode_command() { print opencode; }

agent_opencode_connect() {
  local f=$(opencode_plugin) new
  if [[ $1 == off ]]; then
    [[ -f $f ]] && rm -f $f
    return 0
  fi
  new=${"$(<$COMPANION_DIR/agents/opencode-plugin.js)"//__FROK_EVENT__/$COMPANION_DIR/companion-event.sh}
  [[ -f $f && "$(<$f)" == $new ]] && return 0
  mkdir -p ${f:h}
  print -r -- $new >| $f
  say "companion plugin → ${f/#$HOME/~}"
}

agent_opencode_connected() { [[ -f $(opencode_plugin) ]] && grep -qF $COMPANION_DIR/companion-event.sh $(opencode_plugin); }

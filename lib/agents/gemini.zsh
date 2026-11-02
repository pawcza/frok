# gemini.zsh: Gemini CLI reports through hooks in ~/.gemini/settings.json.
# Antigravity CLI (`agy`), its successor, shares ~/.gemini but keeps hooks
# elsewhere, in a format that takes part in permission decisions, so it's only
# found by process.

AGENT_FEATURES[gemini]="status"
GEMINI_EVENTS='["SessionStart","SessionEnd","BeforeAgent","AfterAgent","BeforeTool","AfterTool","PreCompress","Notification"]'

gemini_settings() { print -r -- $HOME/.gemini/settings.json; }

agent_gemini_present() { has gemini; }
agent_gemini_command() { print gemini; }

agent_gemini_connect() {
  local f=$(gemini_settings) cmd=""
  [[ $1 == on ]] && { cmd=$(agent_hook_cmd gemini); mkdir -p ${f:h}; [[ -f $f ]] || print '{}' >| $f; }
  [[ -f $f ]] || return 0
  json_edit $f --arg cmd "$cmd" --argjson evs $GEMINI_EVENTS "$AGENT_HOOKS_JQ"'
      drop_ours
      | if $cmd == "" then . else add_ours($evs; {hooks:[{type:"command", name:"frok", command:$cmd, timeout:3000}]}) end
      | tidy'
  return 0
}

agent_gemini_connected() { hooks_present $(gemini_settings); }

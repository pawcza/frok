# codex.zsh: Codex CLI reports through hooks in $CODEX_HOME/hooks.json. Codex
# won't run a new or changed hook until you trust it with /hooks, and frok leaves
# that decision with you.

AGENT_FEATURES[codex]="status (after /hooks in Codex)"
CODEX_EVENTS='["SessionStart","SessionEnd","UserPromptSubmit","PreToolUse","PostToolUse","PermissionRequest","PreCompact","PostCompact","SubagentStart","SubagentStop","Stop","Interrupt"]'

codex_hooks_file() { print -r -- ${CODEX_HOME:-$HOME/.codex}/hooks.json; }

agent_codex_present() { has codex; }
agent_codex_command() { print codex; }

agent_codex_connect() {
  local f=$(codex_hooks_file) cmd=""
  [[ $1 == on ]] && { cmd=$(agent_hook_cmd codex); mkdir -p ${f:h}; [[ -f $f ]] || print '{}' >| $f; }
  [[ -f $f ]] || return 0
  # 3 s: the most Codex allows on SessionEnd. Runs in step, so events stay in order.
  if json_edit $f --arg cmd "$cmd" --argjson evs $CODEX_EVENTS "$AGENT_HOOKS_JQ"'
      drop_ours
      | if $cmd == "" then . else add_ours($evs; {hooks:[{type:"command", command:$cmd, timeout:3}]}) end
      | tidy' && [[ $1 == on ]]; then
    step "Codex skips new hooks until you trust them: run /hooks in Codex once"
  fi
  return 0
}

agent_codex_connected() { hooks_present $(codex_hooks_file); }

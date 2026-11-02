# claude.zsh: Claude Code: where its configs live, how you start it, its hooks
# and status line, and the frok skill that lets Claude drive frok for you.

AGENT_FEATURES[claude]="status, context, limits, stats, skill"
COMPANION_EVENTS='["SessionStart","SessionEnd","UserPromptSubmit","PreToolUse","PostToolUse","PostToolUseFailure","PermissionRequest","Notification","SubagentStart","SubagentStop","PreCompact","Stop"]'

# ── Claude Code config dirs (CLAUDE_CONFIG_DIR, ~/.claude, ccs profiles) ──
claude_dirs() {
  local -aU d
  [[ -n $CLAUDE_CONFIG_DIR ]] && d+=($CLAUDE_CONFIG_DIR)
  [[ -d $HOME/.claude ]] && d+=($HOME/.claude)
  d+=($HOME/.ccs/instances/*(N/))
  print -l $d
}

agent_claude_present() { has claude || has ccs || [[ -n $(claude_dirs) ]]; }
agent_claude_command() { print claude; }

# How you start Claude Code: plain `claude`, or a ccs account (`ccs personal`),
# most recently used account first.
claude_choices() {
  if has ccs && [[ -f $HOME/.ccs/config.yaml ]]; then
    awk '/^accounts:/{a=1; next} a && /^[^ #]/{a=0} a && /^  [A-Za-z0-9_-]+:/{n=$1; sub(":","",n)} a && /last_used:/{gsub(/"/,"",$2); print $2, n}' \
      $HOME/.ccs/config.yaml | sort -r | awk '{print "ccs " $2}'
  fi
  has claude && print claude
}

# Hook the companion into every Claude config. Older companion hooks (any
# command ending in companion-event.sh, e.g. the pre-frok install) are replaced.
# Its status line (usage limits, exact context) goes in only where there's no
# status line of your own.
agent_claude_connect() {
  local dir s cmd="" sl=""
  [[ $1 == on ]] && { cmd=$COMPANION_DIR/companion-event.sh; sl=$COMPANION_DIR/statusline.sh; }
  for dir in $(claude_dirs); do
    s=$dir/settings.json
    [[ -f $s ]] || { [[ -n $cmd ]] && print '{}' >| $s || continue }
    json_edit $s --arg cmd "$cmd" --arg sl "$sl" --argjson evs $COMPANION_EVENTS "$AGENT_HOOKS_JQ"'
      drop_ours
      | if $cmd == "" then . else add_ours($evs; {matcher:"", hooks:[{type:"command", command:$cmd, timeout:5, async:true}]}) end
      | tidy
      | if ((.statusLine.command // "") | endswith("/statusline.sh") and (contains("/companion/") or contains("/companions/"))) then del(.statusLine) else . end
      | if $sl != "" and .statusLine == null then .statusLine = {type: "command", command: $sl} else . end'
  done
  [[ $1 == off ]] && { for dir in $(claude_dirs); do [[ -L $dir/skills/frok ]] && rm $dir/skills/frok; done }
  return 0
}

agent_claude_connected() {
  local dir found=0
  for dir in $(claude_dirs); do hooks_present $dir/settings.json || return 1; found=1; done
  (( found ))
}

# ── Claude skill: the guide that drives `frok` for you ───────────────
skill_install() {
  local dir
  agent_disabled claude && return
  for dir in $(claude_dirs); do
    mkdir -p $dir/skills
    [[ -L $dir/skills/frok || ! -e $dir/skills/frok ]] && ln -sfn $FROK_HOME/skill $dir/skills/frok
  done
}

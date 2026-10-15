# companion.zsh — the companion pane: pets, its Claude Code hooks and status
# line, and starting it.

COMPANION_EVENTS='["SessionStart","SessionEnd","UserPromptSubmit","PreToolUse","PostToolUse","PostToolUseFailure","PermissionRequest","Notification","SubagentStart","SubagentStop","PreCompact","Stop"]'

# The companion is one engine (companion/) with a choice of pets.
COMPANION_DIR=$FROK_HOME/companion
companion_names() { local f; for f in $COMPANION_DIR/pets/*.zsh(N); do print ${f:t:r}; done; }
# pet_art <name> — the pet's resting face, for previews
pet_art() {
  ( source $COMPANION_DIR/pets/$1.zsh 2>/dev/null || exit
    local l; for l in "${PET_ART[@]}"; do print -r -- ${${${l//\{1\}/$PET_EYE}//\{2\}/$PET_EYE}//\{m\}/${PET_MOUTH[rest]}}; done )
}

# Hook the companion into every Claude config. Older companion hooks (any
# command ending in companion-event.sh, e.g. the pre-frok install) are replaced.
# Its status line (usage limits, exact context) goes in only where there's no
# status line of your own.
companion_hooks() {
  local name=$1 dir s cmd="" sl="" changed
  [[ $name != none ]] && { cmd=$COMPANION_DIR/companion-event.sh; sl=$COMPANION_DIR/statusline.sh; }
  for dir in $(claude_dirs); do
    s=$dir/settings.json
    [[ -f $s ]] || { [[ -n $cmd ]] && print '{}' >| $s || continue }
    changed=$(jq --arg cmd "$cmd" --arg sl "$sl" --argjson evs $COMPANION_EVENTS '
      def ours: (.command // "") | endswith("companion-event.sh");
      (.hooks // {}) |= (with_entries(.value |= (map(.hooks |= map(select(ours | not))) | map(select((.hooks | length) > 0))))
                         | with_entries(select((.value | length) > 0)))
      | if $cmd == "" then . else
          reduce $evs[] as $e (.; .hooks[$e] = ((.hooks[$e] // []) + [{matcher:"", hooks:[{type:"command", command:$cmd, timeout:5, async:true}]}]))
        end
      | if .hooks == {} then del(.hooks) else . end
      | if ((.statusLine.command // "") | endswith("/statusline.sh") and (contains("/companion/") or contains("/companions/"))) then del(.statusLine) else . end
      | if $sl != "" and .statusLine == null then .statusLine = {type: "command", command: $sl} else . end' $s)
    if [[ $changed != "$(jq . $s)" ]]; then
      cp $s $s.bak.frok
      print -r -- $changed >| $s
      say "companion hooks → ${s/#$HOME/~}"
    fi
  done
}

companion_run() {
  local name=$(cfg .companion); [[ $name == (none|frog) ]] && name=frok
  export FROK_STATE FROK_GEN FROK_CFG FROK_FACTS=$(cfg .facts) FROK_PET=$name
  load_theme $(cfg .theme)                 # chip colours for the companion's footer
  export FROK_UI="${T[hover]} ${T[border]} ${T[accent]} ${T[fg]} ${T[muted]}"
  exec $COMPANION_DIR/companion.zsh
}

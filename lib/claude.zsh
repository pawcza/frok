# claude.zsh — Claude Code: where its configs live, how you start it, and the
# frok skill that lets Claude drive frok for you.

# ── Claude Code config dirs (CLAUDE_CONFIG_DIR, ~/.claude, ccs profiles) ──
claude_dirs() {
  local -aU d
  [[ -n $CLAUDE_CONFIG_DIR ]] && d+=($CLAUDE_CONFIG_DIR)
  [[ -d $HOME/.claude ]] && d+=($HOME/.claude)
  d+=($HOME/.ccs/instances/*(N/))
  print -l $d
}

# How you start Claude Code: plain `claude`, or a ccs account (`ccs personal`),
# most recently used account first.
claude_choices() {
  if has ccs && [[ -f $HOME/.ccs/config.yaml ]]; then
    awk '/^accounts:/{a=1; next} a && /^[^ #]/{a=0} a && /^  [A-Za-z0-9_-]+:/{n=$1; sub(":","",n)} a && /last_used:/{gsub(/"/,"",$2); print $2, n}' \
      $HOME/.ccs/config.yaml | sort -r | awk '{print "ccs " $2}'
  fi
  has claude && print claude
}

# ── Claude skill: the guide that drives `frok` for you ───────────────
skill_install() {
  local dir
  for dir in $(claude_dirs); do
    mkdir -p $dir/skills
    [[ -L $dir/skills/frok || ! -e $dir/skills/frok ]] && ln -sfn $FROK_HOME/skill $dir/skills/frok
  done
}

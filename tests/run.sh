#!/usr/bin/env zsh
# run.sh — frok's tests. Everything runs in a throwaway sandbox (its own HOME,
# config and state), offline, and never touches your setup.
#   tests/run.sh            all of them
#   tests/run.sh pets hook  just those
# Needs zsh, jq, python3 and `script` (util-linux or BSD).
emulate -L zsh; setopt extendedglob
ROOT=${0:A:h:h}; FIX=${0:A:h}/fixtures
SANDBOX=$(mktemp -d); trap 'rm -rf $SANDBOX' EXIT
export HOME=$SANDBOX/home FROK_CONFIG_DIR=$SANDBOX/config FROK_STATE=$SANDBOX/state
unset CLAUDE_CONFIG_DIR FROK_PANE WEZTERM_PANE KITTY_WINDOW_ID
mkdir -p $HOME
US=$'\x1f'; pass=0; fail=0

ok()   { (( pass++ )); print -P "  %F{green}✓%f $1"; }
bad()  { (( fail++ )); print -P "  %F{red}✗%f $1"; [[ -n ${2-} ]] && print -r -- "      $2"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3-}"; fi }   # check <name> <condition> [detail]
field() { print -r -- "${${(ps:$US:)"$(<$1)"}[$2]}"; }              # field <state file> <n>

# script(1) differs between util-linux and BSD/macOS
tty_run() {   # tty_run <rows> <cols> <command> < keys
  if script --version 2>/dev/null | grep -q util-linux; then script -qc "stty rows $1 cols $2; $3" /dev/null
  else script -q /dev/null zsh -c "stty rows $1 cols $2; $3"; fi
}

t_syntax() {
  local f
  for f in $ROOT/bin/frok $ROOT/lib/**/*.zsh $ROOT/companion/*.zsh $ROOT/companion/{parts,pets}/*.zsh $ROOT/shell/frok.sh $ROOT/tests/run.sh; do
    zsh -n $f 2>/dev/null || bad "zsh syntax: ${f#$ROOT/}"
  done
  for f in $ROOT/companion/*.sh; do bash -n $f || bad "bash syntax: ${f#$ROOT/}"; done
  sh -n $ROOT/install.sh || bad "sh syntax: install.sh"
  for f in $ROOT/**/*.py; do python3 -m py_compile $f 2>/dev/null || bad "python syntax: ${f#$ROOT/}"; done
  ok "every script parses"
}

t_themes() {
  local f
  for f in $ROOT/themes/*.json; do
    check "theme ${f:t:r}" "jq -e '(.name|type==\"string\") and ([.bg,.fg,.cursor,.selection]|all(test(\"^#[0-9a-fA-F]{6}$\")))
      and (.ansi|length==8) and (.brights|length==8)
      and ([.ui.surface,.ui.muted,.ui.accent,.ui.accent2,.ui.border,.ui.hover]|all(type==\"string\"))' $f >/dev/null"
  done
}

t_layouts() {
  local f
  for f in $ROOT/layouts/*.json; do
    # every pane after the first splits one defined before it, right or down
    check "layout ${f:t:r}" "jq -e '.panes as \$p | (.focus // \$p[0].id) as \$focus | ([\$p[].id]|length == (unique|length))
      and ([range(1; \$p|length) as \$i | \$p[\$i] | (.dir == \"right\" or .dir == \"down\") and (.size > 0 and .size < 1)
           and ([\$p[:\$i][].id] | index(\$p[\$i].split) != null)] | all)
      and ([\$p[].id] | index(\$focus) != null)' $f >/dev/null"
  done
}

t_pets() {
  local f out
  for f in $ROOT/companion/pets/*.zsh; do
    out=$(zsh -c '
      source $1
      local -a errs; local l i k w
      (( $#PET_ART == 6 )) || errs+=("PET_ART needs 6 rows")
      for k in rest talk open sad happy tongue grit angry; do [[ -n ${PET_MOUTH[$k]} ]] || errs+=("no $k mouth"); done
      w=${#PET_MOUTH[rest]}; for k in ${(k)PET_MOUTH}; do (( ${#PET_MOUTH[$k]} == w )) || errs+=("mouth $k is not $w wide"); done
      for (( i = 1; i <= 6; i++ )); do for l in "${PET_ART[i]}" "${PET_ALT[i]}"; do
        l=${${${l//\{1\}/o}//\{2\}/o}//\{m\}/${PET_MOUTH[rest]}}
        (( ${#l} <= 28 )) || errs+=("row $i is ${#l} wide (max 28)")
        (( i <= 3 )) && [[ -n ${l[1,9]// } ]] && errs+=("row $i uses columns 1-9 (bubbles go there)")
      done; done
      local -a keys names; for k in $PET_TRICKS; do keys+=(${k%%:*}); names+=(${${k#*:}%%:*}); done
      local -aU uniq=($keys); (( ${#keys} == ${#uniq} )) || errs+=("trick keys repeat")
      for k in $keys; do [[ $k == [p,\[\]\ ] ]] && errs+=("key $k is taken by the companion"); done
      for k in $PET_IDLE; do (( ${names[(Ie)$k]} )) || errs+=("idle trick $k is not in PET_TRICKS"); done
      print -rl -- $errs' _ $f)
    if [[ -z $out ]]; then ok "pet ${f:t:r}"; else bad "pet ${f:t:r}" "${out//$'\n'/; }"; fi
  done
}

t_hook() {
  local S=$FROK_STATE/companion/sessions H=$ROOT/companion/companion-event.sh
  ev() { print -r -- "$1" | bash $H; }
  ev '{"hook_event_name":"UserPromptSubmit","session_id":"h1","cwd":"/w/api","prompt":"Fix the token refresh race"}'
  check "prompt → thinking, topic kept" "[[ \$(field $S/h1 2) == thinking && \$(field $S/h1 6) == 'Fix the token refresh race' ]]"
  ev '{"hook_event_name":"PreToolUse","session_id":"h1","cwd":"/w/api","tool_name":"Bash","tool_input":{"command":"npm test"}}'
  check "tool use → working, says what" "[[ \$(field $S/h1 2) == working && \$(field $S/h1 5) == '\$ npm test' ]]"
  ev '{"hook_event_name":"Stop","session_id":"h1","cwd":"/w/api"}'
  ev '{"hook_event_name":"SubagentStop","session_id":"h1","cwd":"/w/api"}'
  check "a subagent finishing after the turn doesn't undo done" "[[ \$(field $S/h1 2) == done ]]"
  ev '{"hook_event_name":"Notification","session_id":"h1","cwd":"/w/api","notification_type":"idle_prompt","message":"Claude is waiting"}'
  check "idle nudges are ignored" "[[ \$(field $S/h1 2) == done ]]"
  ev '{"hook_event_name":"SessionEnd","session_id":"h1","cwd":"/w/api"}'
  check "session end removes it" "[[ ! -e $S/h1 ]]"
  check "bad input never fails Claude" "print -r -- 'not json' | bash $H"
}

t_statusline() {
  local out f=$FROK_STATE/companion/status/s1
  out=$(bash $ROOT/companion/statusline.sh < $FIX/statusline.json)
  check "status line prints model, context and limits" "[[ \${out//$'\e'\[[0-9]m/} == 'Opus · ctx 19% · 5h 23% · 7d 41%' ]]" "got: $out"
  check "keeps context % and both limits" "[[ \$(field $f 2) == 19 && \$(field $f 3) == 23 && \$(field $f 5) == 41 && \$(field $f 6) == 1792400000 ]]"
}

t_stats() {
  # the fixture's day becomes today, so it's inside the 40-day window
  local p=$HOME/.claude/projects/demo day=$(date -u +%F); mkdir -p $p
  sed "s/2026-01-15/$day/g" $FIX/transcript.jsonl > $p/s.jsonl
  TZ=UTC bash $ROOT/companion/stats.sh
  local d=$FROK_STATE/companion/stats/days.json
  # the fixture: one response written as 2 records (counted once), a 2+/1- edit,
  # a 3-line new file, one commit that worked and one whose hook failed
  check "tokens counted once per response" "[[ \$(jq '.\"$day\".tok' $d) == 1400 ]]" "$(<$d)"
  check "lines added/removed" "[[ \$(jq '.\"$day\" | \"\\(.add)/\\(.del)\"' -r $d) == 5/1 ]]"
  check "only successful commits" "[[ \$(jq '.\"$day\".commits' $d) == 1 ]]"
  TZ=UTC bash $ROOT/companion/stats.sh
  check "a second run adds nothing (reads only new bytes)" "[[ \$(jq '.\"$day\".tok' $d) == 1400 ]]"
}

t_companion() {
  local S=$SANDBOX/demo/companion now=$EPOCHSECONDS pet keys out
  mkdir -p $S/sessions $S/status
  print -r -- "$now${US}working${US}t:pts/91$US/w$US\$ npm test${US}Fix the token refresh race$US" > $S/sessions/c1
  print -r -- "$now${US}waiting${US}t:pts/92$US/w${US}needs permission: npm run migrate${US}Add dark mode$US" > $S/sessions/c2
  print -r -- "$now${US}40${US}23$US$(( now + 3600 ))${US}41$US$(( now + 86400 ))${US}test" > $S/status/c1
  for pet in $ROOT/companion/pets/*.zsh(:t:r); do
    keys=$(zsh -c 'source $1; for t in $PET_TRICKS; do print -n ${t%%:*}; done' _ $ROOT/companion/pets/$pet.zsh)
    out=$( { sleep 1; for k in ${(s::)keys} p ']' '['; do printf %s $k; sleep 0.25; done; sleep 0.5 } |
      tty_run 18 120 "FROK_DEMO=1 FROK_STATE=$SANDBOX/demo FROK_FACTS=false FROK_PET=$pet timeout 6 zsh $ROOT/companion/companion.zsh" 2>&1 )
    local errs=${(M)${(f)out}:#*(not found|bad (math|pattern|subscript|substitution)|parse error|no such file)*}
    if [[ -n $errs ]]; then bad "companion with $pet" "${errs[1,200]}"
    elif [[ $out != *"Fix the token refresh race"* || $out != *"needs you"* || $out != *"resets in"* ]]; then bad "companion with $pet: sessions or limits missing"
    else ok "companion with $pet: renders, every trick runs"; fi
  done
}

t_cli() {
  local frok=$ROOT/bin/frok
  check "frok help" "$frok help | grep -q 'frok menu'"
  check "frok status --json" "$frok status --json | jq -e '.available.companions | index(\"octopus\")' >/dev/null"
  check "frok companion lists the pets" "$frok companion | grep -q 'cat frok ghost octopus robot'"
  check "unknown pet is refused" "! $frok companion dragon 2>/dev/null"
}

typeset -a all=(syntax themes layouts pets hook statusline stats companion cli)
for t in ${@:-$all}; do print -P "%B$t%b"; t_$t; done
print; if (( fail )); then print -P "%F{green}$pass passed%f, %F{red}$fail failed%f"; else print -P "%F{green}$pass passed%f"; fi
(( fail == 0 ))

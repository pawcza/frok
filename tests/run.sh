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
field() { local -a a=("${(@ps:$US:)"$(<$1)"}"); print -r -- "${a[$2]}"; }   # field <state file> <n>

# script(1) differs between util-linux and BSD/macOS
tty_run() {   # tty_run <rows> <cols> <command> < keys
  if script --version 2>/dev/null | grep -q util-linux; then script -qc "stty rows $1 cols $2; $3" /dev/null
  else script -q /dev/null zsh -c "stty rows $1 cols $2; $3"; fi
}

t_syntax() {
  local f
  for f in $ROOT/bin/frok $ROOT/lib/**/*.zsh $ROOT/companion/*.zsh $ROOT/companion/{parts,pets,widgets}/*.zsh $ROOT/companion/agents/*.sh $ROOT/shell/frok.sh $ROOT/docs/screenshots/make.sh $ROOT/tests/run.sh; do
    zsh -n $f 2>/dev/null || bad "zsh syntax: ${f#$ROOT/}"
  done
  for f in $ROOT/companion/*.sh $ROOT/companion/agents/*.sh; do bash -n $f || bad "bash syntax: ${f#$ROOT/}"; done
  for f in $ROOT/companion/agents/*.jq; do jq -n -f $f >/dev/null 2>&1 || [[ $? == 5 ]] || bad "jq syntax: ${f#$ROOT/}"; done
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
      for k in $keys; do [[ $k == [p,\[\]\ A-Z] ]] && errs+=("key $k is taken by the companion (widgets use capitals)"); done
      for k in $PET_IDLE; do (( ${names[(Ie)$k]} )) || errs+=("idle trick $k is not in PET_TRICKS"); done
      print -rl -- $errs' _ $f)
    if [[ -z $out ]]; then ok "pet ${f:t:r}"; else bad "pet ${f:t:r}" "${out//$'\n'/; }"; fi
  done
}

t_backgrounds() {
  python3 -c 'import PIL' 2>/dev/null || { ok "backgrounds skipped (no Pillow)"; return }
  local e
  for e in $(PYTHONPATH=$ROOT/backgrounds python3 -m frokbg --list); do
    check "background $e draws a frame" "PYTHONPATH=$ROOT/backgrounds python3 -c '
import importlib; from frokbg.common import Theme
s = importlib.import_module(\"frokbg.$e\").spec(Theme(\"#c0caf5\",\"#7aa2f7\",\"#bb9af7\",\"#1a1b26\"))
f = s.draw(0.5, s.frames // 2); assert f.size == (s.width, s.height)'"
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
  local S=$SANDBOX/demo/companion now=$EPOCHSECONDS pet keys out cfg=$SANDBOX/dash.json
  mkdir -p $S/sessions $S/status $S/widgets
  # every widget on, with weather and news already fetched (demo mode stays offline)
  print -r -- '{"dashboard":["clock","weather","news","system","timer","fact","stats","limits","keys","tricks"],
    "widgets":{"weather":{"city":"Testville"},"clock":{"zones":"Tokyo=Asia/Tokyo"}}}' > $cfg
  print -r -- '{"city":"Testville","units":"metric","place":"Testville","current":{"temperature_2m":18.4,"apparent_temperature":16,"weather_code":2,"wind_speed_10m":9},
    "current_units":{"wind_speed_10m":"km/h"},"daily":{"temperature_2m_max":[21],"temperature_2m_min":[11],"precipitation_probability_max":[10]}}' > $S/widgets/weather.json
  print -r -- "HN${TAB:-	}A test headline${TAB:-	}https://example.com" > $S/widgets/news.tsv
  print -r -- "$now${US}working${US}t:pts/91$US/w$US\$ npm test${US}Fix the token refresh race$US" > $S/sessions/c1
  print -r -- "$now${US}waiting${US}t:pts/92$US/w${US}needs permission: npm run migrate${US}Add dark mode$US" > $S/sessions/c2
  print -r -- "$now${US}40${US}23$US$(( now + 3600 ))${US}41$US$(( now + 86400 ))${US}test" > $S/status/c1
  for pet in $ROOT/companion/pets/*.zsh(:t:r); do
    keys=$(zsh -c 'source $1; for t in $PET_TRICKS; do print -n ${t%%:*}; done' _ $ROOT/companion/pets/$pet.zsh)
    out=$( { sleep 1; for k in ${(s::)keys} p ']' '[' N T; do printf %s $k; sleep 0.25; done; sleep 0.8 } |
      tty_run 30 120 "FROK_DEMO=1 FROK_CFG=$cfg FROK_STATE=$SANDBOX/demo FROK_FACTS=false FROK_PET=$pet timeout 7 zsh $ROOT/companion/companion.zsh" 2>&1 )
    local errs=${(M)${(f)out}:#*(not found|bad (math|pattern|subscript|substitution)|parse error|no such file)*}
    if [[ -n $errs ]]; then bad "companion with $pet" "${errs[1,200]}"
    elif [[ $out != *"Fix the token refresh race"* || $out != *"needs you"* || $out != *"resets in"* ]]; then bad "companion with $pet: sessions or limits missing"
    elif [[ $out != *"18°"* || $out != *"A test headline"* || $out != *"Tokyo"* || $out != *"mem "* || $out != *" left"* ]]; then bad "companion with $pet: a widget is missing (weather, news, clock, system or a running timer)"
    else ok "companion with $pet: every widget renders, every trick and key runs"; fi
    rm -f $S/widgets/timer
  done
}

t_widgets() {
  local f n
  for f in $ROOT/companion/widgets/*.zsh; do
    n=${f:t:r}
    check "widget $n: described and drawable" "[[ \$(sed -n 1p $f) == '# $n — '* ]] && grep -q '^w_${n}_render()' $f"
  done
  local out; out=$(python3 $ROOT/companion/widgets/news-fetch.py "file://$FIX/feed.xml")
  check "feeds: headlines with their links" "[[ \$out == *'Plain headline'*'https://example.com/a'* ]]" "$out"
  check "feeds: control characters stripped from titles" "[[ \$out != *$'\\u009b'* && \$out == *'Sneaky 2Jcleared'* ]]"
  check "feeds: only http(s) links" "[[ \$out != *javascript* ]]"
}

t_dashboard() {
  local frok=$ROOT/bin/frok
  $frok dashboard add weather 1 >/dev/null; $frok dashboard set weather city Testville >/dev/null
  $frok dashboard move fact 6 >/dev/null; $frok dashboard remove keys >/dev/null
  check "add / move / remove keep the order" "[[ \$(jq -c .dashboard $FROK_CONFIG_DIR/frok.json) == '[\"weather\",\"stats\",\"limits\",\"tricks\",\"fact\"]' ]]" "$(jq -c .dashboard $FROK_CONFIG_DIR/frok.json)"
  check "set stores an option" "[[ \$(jq -r .widgets.weather.city $FROK_CONFIG_DIR/frok.json) == Testville ]]"
  $frok dashboard set weather city "" >/dev/null
  check "an empty value clears it" "[[ \$(jq -r '.widgets.weather.city // \"gone\"' $FROK_CONFIG_DIR/frok.json) == gone ]]"
  check "unknown widgets are refused" "! $frok dashboard add teleport 2>/dev/null"
  $frok dashboard reset >/dev/null
  check "reset brings back the defaults" "[[ \$(jq -c .dashboard $FROK_CONFIG_DIR/frok.json) == '[\"fact\",\"stats\",\"limits\",\"keys\",\"tricks\"]' ]]"
}

t_cli() {
  local frok=$ROOT/bin/frok
  check "frok help" "$frok help | grep -q 'frok menu'"
  check "frok status --json" "$frok status --json | jq -e '.available.companions | index(\"octopus\")' >/dev/null"
  check "frok companion lists the pets" "$frok companion | grep -q 'cat frok ghost octopus robot'"
  check "unknown pet is refused" "! $frok companion dragon 2>/dev/null"
}

# ── the agent layer: what each agent's own payloads turn into ──────────────
AFX=$FIX/agents
# no_agents_path: PATH without any coding agent on it (the machine running the tests may have some)
no_agents_path() {
  local d; local -a keep
  for d in $path; do [[ -x $d/claude || -x $d/ccs || -x $d/codex || -x $d/gemini || -x $d/opencode || -x $d/aider || -x $d/agy ]] || keep+=($d); done
  print -r -- ${(j.:.)keep}
}
# after <jsonl> <n> <agent>: replay the first n payloads through the hook
after() { head -n $2 $1 | while IFS= read -r l; do print -r -- "$l" | bash $ROOT/companion/companion-event.sh $3; done; }

t_agent_detection() {
  local -a table=(
    'claude|/home/u/.local/bin/claude'
    'claude|node /usr/lib/node_modules/@anthropic-ai/claude-code/cli.js --resume'
    'codex|codex'
    'codex|node /usr/local/bin/codex'
    'codex|/usr/lib/node_modules/@openai/codex/vendor/x86_64/codex/codex resume'
    'gemini|node /usr/local/bin/gemini'
    'gemini|node --max-old-space-size=8192 /usr/lib/node_modules/@google/gemini-cli/bundle/gemini.js'
    'opencode|opencode'
    'opencode|/usr/lib/node_modules/opencode-ai/bin/.opencode'
    'aider|/home/u/.local/share/uv/tools/aider-chat/bin/python /home/u/.local/bin/aider --model x'
    'aider|python3 -m aider'
    'agy|agy'
    '|vim codex.py'
    '|less aider'
    '|python3 manage.py runserver'
    '|node server.js'
    '|bash'
  ) row
  for row in $table; do
    local got=$(zsh -c 'source $1; shift; agent_of ${=1}; print -r -- $AGENT_ID' _ $ROOT/companion/agents/agents.sh "${row#*|}")
    check "process: ${row#*|} → ${row%%|*:-nothing}" "[[ '$got' == '${row%%|*}' ]]" "got: $got"
  done
  local got=$(FROK_AGENT_WATCH="amp goose" zsh -c 'source $1; agent_of /opt/bin/goose session; print -r -- $AGENT_ID' _ $ROOT/companion/agents/agents.sh)
  check "a watched command counts as an agent" "[[ $got == goose ]]" "got: $got"
}

t_agent_codex() {
  local S=$FROK_STATE/companion/sessions f=$AFX/codex.jsonl
  after $f 1 codex;  check "codex: session start → idle, marked as codex" "[[ \$(field $S/cx1 2) == idle && \$(field $S/cx1 8) == codex ]]"
  after $f 2 codex;  check "codex: prompt → thinking, topic kept" "[[ \$(field $S/cx1 2) == thinking && \$(field $S/cx1 6) == 'Fix the login redirect' ]]"
  after $f 3 codex;  check "codex: shell → working, says what" "[[ \$(field $S/cx1 2) == working && \$(field $S/cx1 5) == '\$ npm test' ]]"
  after $f 5 codex;  check "codex: apply_patch names the file" "[[ \$(field $S/cx1 5) == 'Edit login.ts' ]]" "$(field $S/cx1 5)"
  after $f 6 codex;  check "codex: permission → needs you" "[[ \$(field $S/cx1 2) == waiting && \$(field $S/cx1 5) == *'rm -rf build'* ]]"
  after $f 7 codex;  check "codex: MCP tool by its short name" "[[ \$(field $S/cx1 5) == read_file ]]"
  after $f 8 codex;  check "codex: compacting" "[[ \$(field $S/cx1 2) == dizzy ]]"
  after $f 10 codex; check "codex: stop → done" "[[ \$(field $S/cx1 2) == done ]]"
  after $f 12 codex; check "codex: an interrupt ends the turn" "[[ \$(field $S/cx1 2) == done ]]"
  after $f 13 codex; check "codex: session end removes it" "[[ ! -e $S/cx1 ]]"
  check "codex: a null transcript path stays empty" "[[ -z \$(print -r -- '{\"hook_event_name\":\"Stop\",\"session_id\":\"cx2\",\"cwd\":\"/w\",\"transcript_path\":null}' | bash $ROOT/companion/companion-event.sh codex; field $S/cx2 7) ]]"
}

t_agent_gemini() {
  local S=$FROK_STATE/companion/sessions f=$AFX/gemini.jsonl
  check "gemini: the hook prints nothing (its stdout must stay JSON only)" "[[ -z \$(head -n 2 $f | tail -n 1 | bash $ROOT/companion/companion-event.sh gemini) ]]"
  after $f 2 gemini; check "gemini: prompt → thinking, topic kept" "[[ \$(field $S/gm1 2) == thinking && \$(field $S/gm1 6) == 'Add dark mode' && \$(field $S/gm1 8) == gemini ]]"
  after $f 3 gemini; check "gemini: shell tool → working, says what" "[[ \$(field $S/gm1 2) == working && \$(field $S/gm1 5) == '\$ npm run build' ]]"
  after $f 5 gemini; check "gemini: replace → Edit <file>" "[[ \$(field $S/gm1 5) == 'Edit theme.css' ]]" "$(field $S/gm1 5)"
  after $f 6 gemini; check "gemini: a failed tool → error" "[[ \$(field $S/gm1 2) == error ]]"
  after $f 7 gemini; check "gemini: permission notification → needs you" "[[ \$(field $S/gm1 2) == waiting && \$(field $S/gm1 5) == *requires\ permission* ]]"
  after $f 8 gemini; check "gemini: compressing" "[[ \$(field $S/gm1 2) == dizzy ]]"
  after $f 9 gemini; check "gemini: agent finished → done" "[[ \$(field $S/gm1 2) == done ]]"
  after $f 10 gemini; check "gemini: session end removes it" "[[ ! -e $S/gm1 ]]"
}

t_agent_opencode() {
  (( $+commands[node] )) || { ok "opencode plugin skipped (no node)"; return }
  local S=$FROK_STATE/companion/sessions plugin=$SANDBOX/frok-companion.mjs
  sed "s|__FROK_EVENT__|$ROOT/companion/companion-event.sh|" $ROOT/companion/agents/opencode-plugin.js > $plugin
  # run the real plugin against opencode's event shapes, stopping after line n
  play() { node --input-type=module -e '
    import { readFileSync } from "node:fs"
    const [plugin, file, n] = process.argv.slice(1)
    const { FrokCompanion } = await import(plugin)
    const hooks = await FrokCompanion({ directory: "/w/cli" })
    for (const line of readFileSync(file, "utf8").trim().split("\n").slice(0, +n)) {
      const e = JSON.parse(line)
      if (e.kind === "event") await hooks.event({ event: e.event })
      else await hooks[`tool.execute.${e.kind}`](e.input, e.output)
      await new Promise(r => setTimeout(r, 60))
    }
    await new Promise(r => setTimeout(r, 250))' $plugin $AFX/opencode.jsonl $1; }
  rm -f $S/ses_1
  play 3;  check "opencode: busy → thinking, session title kept" "[[ \$(field $S/ses_1 2) == thinking && \$(field $S/ses_1 6) == 'Rename the config flag' && \$(field $S/ses_1 8) == opencode ]]" "$(<$S/ses_1)"
  play 4;  check "opencode: tool → working, says what" "[[ \$(field $S/ses_1 2) == working && \$(field $S/ses_1 5) == '\$ cargo test' ]]"
  play 6;  check "opencode: edit names the file" "[[ \$(field $S/ses_1 5) == 'Edit flags.rs' ]]"
  play 7;  check "opencode: permission → needs you" "[[ \$(field $S/ses_1 2) == waiting && \$(field $S/ses_1 5) == *'rm -rf target'* ]]"
  play 9;  check "opencode: a retry says why" "[[ \$(field $S/ses_1 2) == thinking && \$(field $S/ses_1 5) == 'retrying: rate limited' ]]"
  play 10; check "opencode: a session error → error" "[[ \$(field $S/ses_1 2) == error && \$(field $S/ses_1 5) == 'failed: ProviderAuthError' ]]"
  play 11; check "opencode: idle → done" "[[ \$(field $S/ses_1 2) == done ]]"
  play 14; check "opencode: subagent sessions and streaming events don't appear" "[[ ! -e $S/ses_2 && \$(field $S/ses_1 2) == done ]]"
  play 15; check "opencode: session deleted removes it" "[[ ! -e $S/ses_1 ]]"
}

# The rest of a real path: a process named like the agent, in a terminal, seen by
# the companion. Its stand-in does what aider does: run the command through a shell.
fake_python() {   # fake_python <name> [shell command to run first]
  { print '#!/usr/bin/env python3'; print 'import subprocess, time'
    [[ -n ${2-} ]] && print -r -- "subprocess.run(\"$2\", shell=True, capture_output=True)"
    print 'time.sleep(8)'; } > $SANDBOX/bin/$1
  chmod +x $SANDBOX/bin/$1
}

t_agent_panes() {
  mkdir -p $SANDBOX/bin $SANDBOX/watch/companion
  local out st=$SANDBOX/watch cfg=$SANDBOX/watch.json np=$(no_agents_path)
  print -r -- '{"dashboard":["stats","limits","keys"]}' > $cfg
  # the companion sees only this terminal: real agents on this machine stay out of the test
  mkdir -p $SANDBOX/shim
  { print '#!/bin/sh'; print 'case $1 in -Ao*) ;; *) exec '$commands[ps]' "$@" ;; esac'
    print 't=$(tty | sed s,/dev/,,); '$commands[ps]' "$@" | grep -F " $t "'; } > $SANDBOX/shim/ps
  chmod +x $SANDBOX/shim/ps; np=$SANDBOX/shim:$np
  fake_python agy
  out=$(print | tty_run 24 120 "PATH='$np'; FROK_STATE=$st FROK_CFG=$cfg $SANDBOX/bin/agy & sleep 0.3; FROK_STATE=$st FROK_CFG=$cfg FROK_FACTS=false timeout 4 zsh $ROOT/companion/companion.zsh" 2>&1)
  check "an agent with no reporting shows as running" "[[ \$out == *'Antigravity'* && \$out == *running* ]]" "${out[1,300]}"
  check "…with no context bar, limits or stats" "[[ \$out != *ctx:* && \$out != *resets* && \$out != *tokens* && \$out != *counting* ]]"
  rm -rf $st/companion/sessions
  fake_python aider "bash $ROOT/companion/companion-event.sh aider"
  out=$(print | tty_run 24 120 "PATH='$np'; FROK_STATE=$st FROK_CFG=$cfg $SANDBOX/bin/aider & sleep 0.5; FROK_STATE=$st FROK_CFG=$cfg FROK_FACTS=false timeout 4 zsh $ROOT/companion/companion.zsh" 2>&1)
  check "aider: its notification command finds the pane" "[[ \$out == *'ready for your next prompt'* && \$out == *done* ]]" "${out[1,300]}"
  check "aider: no hook output, no terminal noise from the hook" "[[ -z \$(bash $ROOT/companion/companion-event.sh aider </dev/null) ]]"
}

t_agent_only_claude_features() {
  local S=$SANDBOX/mixed/companion now=$EPOCHSECONDS out cfg=$SANDBOX/mixed.json np=$(no_agents_path)
  mkdir -p $S/sessions $S/status $S/stats
  print -r -- '{"dashboard":["stats","limits","keys"]}' > $cfg
  print -r -- '{}' > $S/stats/days.json
  print -r -- "$now${US}working${US}t:pts/91$US/w$US\$ npm test${US}Fix the login redirect$US${US}codex" > $S/sessions/c1
  out=$(print | tty_run 24 120 "PATH='$np'; FROK_DEMO=1 FROK_CFG=$cfg FROK_STATE=$SANDBOX/mixed FROK_FACTS=false timeout 2 zsh $ROOT/companion/companion.zsh" 2>&1)
  check "codex only: its session shows" "[[ \$out == *'Fix the login redirect'* ]]"
  check "codex only: no limits, stats, zeros or context" "[[ \$out != *'limits'* && \$out != *'stats '* && \$out != *tokens* && \$out != *'0%'* && \$out != *ctx:* && \$out != *Claude* ]]" "${out[1,400]}"
  print -r -- "$now${US}done${US}t:pts/92$US/w${US}finished${US}Write the docs$US${US}claude" > $S/sessions/c2
  print -r -- "$now${US}40${US}23$US$(( now + 3600 ))${US}41$US$(( now + 86400 ))${US}test" > $S/status/c2
  out=$(print | tty_run 24 120 "PATH='$np'; FROK_DEMO=1 FROK_CFG=$cfg FROK_STATE=$SANDBOX/mixed FROK_FACTS=false timeout 2 zsh $ROOT/companion/companion.zsh" 2>&1)
  check "mixed: each row says which agent, Claude's bar and limits stay" "[[ \$out == *Codex* && \$out == *'Claude Code'* && \$out == *ctx:* && \$out == *'resets in'* ]]"
}

t_no_agents() {
  local out st=$SANDBOX/noagent cfg=$SANDBOX/noagent.json np=$(no_agents_path) frok=$ROOT/bin/frok
  mkdir -p $st/companion
  print -r -- '{"dashboard":["fact","stats","limits","keys","tricks"]}' > $cfg
  out=$(print | tty_run 24 120 "PATH='$np'; FROK_DEMO=1 FROK_CFG=$cfg FROK_STATE=$st FROK_DEMO_FACT='A test fact.' FROK_PET=cat timeout 2 zsh $ROOT/companion/companion.zsh" 2>&1)
  check "no agents: the pet and the rest of the dashboard draw" "[[ \$out == *'no agent sessions running'* && \$out == *'A test fact.'* && \$out == *keys* ]]" "${out[1,300]}"
  check "no agents: stats and limits stay out of it" "[[ \$out != *tokens* && \$out != *resets* && \$out != *counting* && \$out != *Claude* ]]"
  local saved=$PATH oldhome=$HOME; PATH=$np; HOME=$SANDBOX/home3; mkdir -p $HOME; rehash
  check "no agents: status says so, nothing is installed" "$frok status --json | jq -e '[.agents[].installed] | any | not' >/dev/null"
  check "no agents: panes fall back to a shell" "$frok status | grep -q 'none found'"
  check "no agents: frok agents still lists them" "$frok agents | grep -q 'Codex .*not installed'"
  check "no agents: nothing to connect, nothing created" "[[ ! -e \$HOME/.claude && ! -e \$HOME/.codex && ! -e \$HOME/.gemini ]]"
  PATH=$saved; HOME=$oldhome; rehash
}

t_agent_connect() {
  local frok=$ROOT/bin/frok saved=$PATH h=$SANDBOX/home2 oldhome=$HOME c
  mkdir -p $SANDBOX/fakebin $h
  for c in codex gemini opencode aider; do print '#!/bin/sh' > $SANDBOX/fakebin/$c; chmod +x $SANDBOX/fakebin/$c; done
  PATH=$SANDBOX/fakebin:$(no_agents_path); HOME=$h; rehash

  mkdir -p $h/.codex; print -r -- '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"my-own-hook"}]}]}}' > $h/.codex/hooks.json
  $frok agents on codex >/dev/null
  local f=$h/.codex/hooks.json
  check "codex: every event hooked, your hook kept" "jq -e '(.hooks | keys | length) == 12 and (.hooks.Stop | length) == 2 and .hooks.Stop[0].hooks[0].command == \"my-own-hook\" and (.hooks.Stop[1].hooks[0].timeout == 3)' $f >/dev/null" "$(<$f)"
  check "codex: the hook is told it's codex" "jq -e '.hooks.Stop[1].hooks[0].command | endswith(\"companion-event.sh codex\")' $f >/dev/null"
  $frok agents on codex >/dev/null
  check "codex: connecting twice adds nothing" "jq -e '(.hooks.Stop | length) == 2' $f >/dev/null"
  check "frok agents reports it connected" "$frok agents | grep -q 'Codex .*connected'"
  $frok agents off codex >/dev/null
  check "codex: off removes only ours" "[[ \$(jq -c . $f) == '{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"my-own-hook\"}]}]}}' ]]" "$(<$f)"
  check "codex: off is remembered" "jq -e '.agents_off == [\"codex\"]' $FROK_CONFIG_DIR/frok.json >/dev/null"
  $frok agents on codex >/dev/null

  mkdir -p $h/.gemini; print -r -- '{"theme":"dark"}' > $h/.gemini/settings.json
  $frok agents on gemini >/dev/null
  f=$h/.gemini/settings.json
  check "gemini: hooks added beside your settings, timeout in ms" "jq -e '.theme == \"dark\" and (.hooks | keys | length) == 8 and .hooks.BeforeTool[0].hooks[0].timeout == 3000' $f >/dev/null" "$(<$f)"
  $frok agents off gemini >/dev/null
  check "gemini: off leaves your settings as they were" "[[ \$(jq -c . $f) == '{\"theme\":\"dark\"}' ]]"
  $frok agents on gemini >/dev/null
  print -r -- '{ // a comment
    "theme": "dark" }' > $f
  $frok agents on gemini >/dev/null 2>&1
  check "gemini: a settings file with comments is left alone" "grep -q 'a comment' $f"

  $frok agents on opencode >/dev/null
  f=$h/.config/opencode/plugins/frok-companion.js
  check "opencode: the plugin knows where the hook is" "grep -qF $ROOT/companion/companion-event.sh $f && ! grep -q __FROK_EVENT__ $f"
  $frok agents off opencode >/dev/null
  check "opencode: off removes the plugin" "[[ ! -e $f ]]"

  f=$h/.aider.conf.yml
  print -r -- 'model: sonnet' > $f
  $frok agents on aider >/dev/null
  check "aider: a marked block beside your settings" "grep -qx 'model: sonnet' $f && grep -q 'notifications-command: .*companion-event.sh aider' $f"
  $frok agents on aider >/dev/null
  check "aider: connecting twice adds nothing" "[[ \$(grep -c '^notifications:' $f) == 1 ]]"
  $frok agents off aider >/dev/null
  check "aider: off leaves your settings as they were" "[[ \$(<$f) == 'model: sonnet' ]]"
  print -r -- 'notifications-command: say done' > $f
  $frok agents on aider >/dev/null 2>&1
  check "aider: your own notification command is left alone" "[[ \$(<$f) == 'notifications-command: say done' ]]"
  rm $f

  $frok agents watch goose >/dev/null
  check "watch: stored, and shown in the list" "$frok agents | grep -q 'goose .*watched'"
  $frok agents unwatch goose >/dev/null
  check "watch: unwatch removes it" "jq -e '.agents_watch == []' $FROK_CONFIG_DIR/frok.json >/dev/null"
  check "unknown agents are refused" "! $frok agents on teleport 2>/dev/null"

  rm -f $h/.gemini/settings.json
  check "with claude absent, panes run the first agent found" "$frok status | grep -q 'agent: codex'"
  PATH=$saved; HOME=$oldhome; rehash
}

# An agent's settings are its own: frok asks once, and a theme change never asks.
t_agent_consent() {
  local oldhome=$HOME saved=$PATH h=$SANDBOX/consent bin=$SANDBOX/consent-bin f
  local cfg=$SANDBOX/consent-config/frok.json
  mkdir -p $h $bin $SANDBOX/consent-config
  for f in codex gemini; do print '#!/bin/sh' > $bin/$f; chmod +x $bin/$f; done
  local clean=$(no_agents_path)
  HOME=$h; PATH=$bin:$clean; rehash
  ask='source $ROOT/lib/core.zsh; for l in $ROOT/lib/*.zsh; do [[ $l == */core.zsh ]] || source $l; done; cfg_init'
  run() { FROK_HOME=$ROOT FROK_CONFIG_DIR=$SANDBOX/consent-config ROOT=$ROOT zsh -c "$ask; $1" </dev/null 2>&1; }

  local out=$(run 'agents_ask')
  check "no terminal: says how to connect" "[[ \$out == *'frok agents on'* ]]" "$out"
  run 'agents_connect pet' >/dev/null
  check "no terminal: nothing is written" "[[ ! -e $h/.codex/hooks.json && ! -e $h/.gemini/settings.json ]]"
  check "no terminal: no answer is stored" "[[ \$(jq -c '.agents_on // []' $cfg) == '[]' && \$(jq -c '.agents_off // []' $cfg) == '[]' ]]"

  run 'agents_ask --yes; agents_connect pet' >/dev/null
  check "--yes connects what it finds" "[[ -e $h/.codex/hooks.json ]] && jq -e '.hooks' $h/.gemini/settings.json >/dev/null"
  check "--yes remembers them" "jq -e '.agents_on == [\"codex\",\"gemini\"]' $cfg >/dev/null"

  FROK_CONFIG_DIR=$SANDBOX/consent-config $ROOT/bin/frok agents off codex >/dev/null
  run 'agents_ask --yes; agents_connect pet' >/dev/null
  check "off beats --yes" "jq -e '.agents_off == [\"codex\"] and .agents_on == [\"gemini\"]' $cfg >/dev/null"

  jq '.agents_on = [] | .agents_off = []' $cfg > $cfg.new && mv $cfg.new $cfg
  FROK_CONFIG_DIR=$SANDBOX/consent-config $ROOT/bin/frok agents on gemini >/dev/null
  jq '.agents_on = []' $cfg > $cfg.new && mv $cfg.new $cfg
  run 'agents_ask' >/dev/null
  check "already connected counts as yes" "jq -e '.agents_on == [\"gemini\"]' $cfg >/dev/null"

  rm -f $h/.codex/hooks.json
  print -r -- "$ask; agents_ask" > $SANDBOX/consent-ask.zsh
  { sleep 2; print n; sleep 1 } | tty_run 24 80 "HOME=$h PATH='$bin:$clean' FROK_HOME=$ROOT FROK_CONFIG_DIR=$SANDBOX/consent-config ROOT=$ROOT zsh $SANDBOX/consent-ask.zsh" >/dev/null 2>&1
  check "no at the prompt is remembered" "jq -e '.agents_off | index(\"codex\")' $cfg >/dev/null"
  PATH=$saved; HOME=$oldhome; rehash
}

typeset -a all=(syntax themes layouts pets widgets backgrounds hook statusline stats companion dashboard cli
  agent_detection agent_codex agent_gemini agent_opencode agent_consent agent_panes agent_only_claude_features no_agents agent_connect)
for t in ${@:-$all}; do print -P "%B$t%b"; t_$t; done
print; if (( fail )); then print -P "%F{green}$pass passed%f, %F{red}$fail failed%f"; else print -P "%F{green}$pass passed%f"; fi
(( fail == 0 ))

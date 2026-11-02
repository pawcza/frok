#!/bin/bash
# companion-event.sh [agent]: bridge between a coding agent and the companion.
# The agent runs this on each event, with a JSON payload on stdin (aider sends
# nothing: its notification command has no payload). agents/<agent>.jq maps the
# payload onto Claude Code's event names, and the result is ONE small state file
# per session in $STATE/companion/sessions/<session_id>:
#   <ts>\x1f<state>\x1f<pane: WezTerm pane id, k<id> for a kitty window, t:<tty> elsewhere>\x1f<cwd>\x1f<what it's doing>\x1f<topic: the agent's title for the session, else the start of the latest prompt>\x1f<transcript path>\x1f<agent>
# plus the legacy global companion.state (used by the WezTerm status-bar face).
# Fast, and exits 0 no matter what (a hook must never block an agent).
set -u
AGENT="${1:-claude}"
case "$AGENT" in claude|codex|gemini|opencode|aider) ;; *) exit 0 ;; esac
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || exit 0
DIR="${FROK_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/frok}/companion"
SDIR="$DIR/sessions"
mkdir -p "$SDIR" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0
. "$HERE/agents/agents.sh"
US=$'\x1f'

# which terminal pane is this? kitty sets TERM=xterm-kitty; WezTerm's env can leak
# into kitty when it's launched from a WezTerm shell, so check kitty first.
find_pane() {
  if [ "${TERM:-}" = xterm-kitty ] && [ -n "${KITTY_WINDOW_ID:-}" ]; then PANE="k$KITTY_WINDOW_ID"
  elif [ -n "${WEZTERM_PANE:-}" ]; then PANE="$WEZTERM_PANE"
  else                                   # any other terminal: use the tty of our agent ancestor
    PANE=""; p=$PPID
    for _ in 1 2 3 4 5 6 7 8; do
      [ -z "$p" ] || [ "$p" -le 1 ] && break
      agent_of $(ps -o args= -p "$p" 2>/dev/null)
      if [ "$AGENT_ID" = "$AGENT" ]; then
        t=$(ps -o tty= -p "$p" 2>/dev/null | tr -d ' ')
        case "$t" in ''|'?'|'??') ;; *) PANE="t:$t"; break ;; esac
      fi
      p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    done
  fi
}

if [ "$AGENT" = aider ]; then
  # one event only: aider is ready for you. No session id either, so the pane is the session.
  find_pane
  EV=Stop; CWD=$PWD; TOOL=""; TARGET=""; PROMPT=""; MSG=""; NTYPE=""; TPATH=""; TITLE=""
  SID="aider-${PANE:-$PPID}"
else
  [ -t 0 ] && exit 0
  IN="$(cat 2>/dev/null)"
  # One jq pass: event, session, cwd, tool, its main target, prompt, message, type, transcript, title.
  IFS="$US" read -r EV SID CWD TOOL TARGET PROMPT MSG NTYPE TPATH TITLE < <(printf '%s' "$IN" | jq -r \
    "$(<"$HERE/agents/$AGENT.jq") | map((. // \"\") | tostring | gsub(\"[\\t\\n\\r\\u001f]+\"; \" \")) | join(\"\\u001f\")" 2>/dev/null)
fi
SID="${SID:-}"; SID="${SID//[^A-Za-z0-9._-]/-}"          # it becomes a file name
[ -z "$SID" ] && exit 0
F="$SDIR/$SID"

short() { local s="$1" n="$2"; [ ${#s} -gt "$n" ] && s="${s:0:$((n-1))}…"; printf '%s' "$s"; }
tooldesc() {
  case "$TOOL" in
    Bash)                         printf '$ %s' "$(short "$TARGET" 60)" ;;
    Edit|MultiEdit|Write|Read|NotebookEdit) printf '%s %s' "$TOOL" "$(basename "$TARGET")" ;;
    Grep|Glob)                    printf '%s %s' "$TOOL" "$(short "$TARGET" 40)" ;;
    WebFetch)                     printf 'fetch %s' "$(short "$TARGET" 50)" ;;
    WebSearch)                    printf 'search “%s”' "$(short "$TARGET" 45)" ;;
    Task|Agent)                   printf 'agent: %s' "$(short "$TARGET" 45)" ;;
    mcp__*)                       printf '%s' "${TOOL##*__}" ;;
    *)                            printf '%s' "$TOOL" ;;
  esac
}
prev_detail() { [ -f "$F" ] && IFS="$US" read -r _ _ _ _ d _ < "$F" && printf '%s' "$d"; }
topic=""; [ -f "$F" ] && IFS="$US" read -r _ _ _ _ _ topic _ < "$F"

detail=""
case "$EV" in
  SessionStart)       state=idle;      detail="session started" ;;
  UserPromptSubmit)
    state=thinking
    case "$PROMPT" in
      "<task-notification"*) detail="background task update" ;;
      "<"*)                  detail="system message" ;;
      *)                     detail="“$(short "$PROMPT" 55)”"; topic="$(short "$PROMPT" 70)" ;;
    esac ;;
  Busy)               state=thinking;  detail="${MSG:-$(prev_detail)}" ;;
  PreToolUse)         state=working;   detail="$(tooldesc)" ;;
  PostToolUse)        state=thinking;  detail="$(prev_detail)" ;;
  PostToolUseFailure) state=error;     detail="failed: $(tooldesc)" ;;
  SubagentStart)      state=working;   detail="running a subagent" ;;
  SubagentStop)
    # after the turn has ended (e.g. Claude Code's away summary) a subagent
    # finishing doesn't wake the session back up
    prev=""; [ -f "$F" ] && IFS="$US" read -r _ prev _ < "$F"
    case "$prev" in done|idle) exit 0 ;; esac
    state=thinking;  detail="subagent finished" ;;
  PermissionRequest)  state=waiting;   detail="needs permission: $(tooldesc)" ;;
  Notification)
    case "${NTYPE:-}" in
      # "Claude is waiting for your input" is sent ~a minute after a turn ends
      # (even with background tasks running) — not an actual request for you.
      idle_prompt|auth_success) exit 0 ;;
      *) state=waiting; detail="$(short "${MSG:-needs your input}" 60)" ;;
    esac ;;
  Error)              state=error;     detail="failed: $(short "${MSG:-unknown error}" 50)" ;;
  PreCompact)         state=dizzy;     detail="compacting context" ;;
  Stop)               state=done;      detail="finished" ;;
  SessionEnd)         rm -f "$F"; state=sleep ;;
  *)                  exit 0 ;;
esac
[ -n "${TITLE:-}" ] && topic="$TITLE"
[ "$AGENT" = aider ] && detail="ready for your next prompt"
# Claude's own title for the conversation (what it puts on the pane) lives in the transcript
if [ "$AGENT" = claude ] && [ -n "${TPATH:-}" ] && [ -r "$TPATH" ]; then
  t=$(grep -o '"aiTitle":"[^"]*"' "$TPATH" 2>/dev/null | tail -n 1)
  t=${t#'"aiTitle":"'}; t=${t%'"'}
  [ -n "$t" ] && topic="$t"
fi

[ "$AGENT" = aider ] || find_pane
now=$(date +%s)
if [ "$EV" != "SessionEnd" ]; then
  printf '%s\n' "$now$US$state$US$PANE$US$CWD$US$detail$US$topic$US${TPATH:-}$US$AGENT" > "$F.tmp" 2>/dev/null \
    && mv -f "$F.tmp" "$F" 2>/dev/null
fi
printf '%s %s\n' "$now" "$state" > "$DIR/companion.state" 2>/dev/null || true
exit 0

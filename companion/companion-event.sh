#!/bin/bash
# companion-event.sh — bridge between Claude Code hooks and the companion.
# Claude Code pipes the hook payload as JSON on stdin. We keep ONE small state
# file per session in ~/.config/terminal/sessions/<session_id>:
#   <ts>\x1f<state>\x1f<pane: WezTerm pane id, or k<id> for a kitty window>\x1f<cwd>\x1f<what it's doing>\x1f<topic: Claude's title for the session, else the start of the latest prompt>\x1f<transcript path>
# plus the legacy global companion.state (used by the WezTerm status-bar face).
# Fast, and exits 0 no matter what (a hook must never block Claude).
set -u
DIR="${FROK_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/frok}/companion"
SDIR="$DIR/sessions"
mkdir -p "$SDIR" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0
[ -t 0 ] && exit 0
IN="$(cat 2>/dev/null)"
US=$'\x1f'

# One jq pass: event, session, cwd, tool, the tool's main target, prompt, message.
IFS="$US" read -r EV SID CWD TOOL TARGET PROMPT MSG NTYPE TPATH < <(printf '%s' "$IN" | jq -r '
  def s: (. // "") | tostring | gsub("[\t\n\r\u001f]+"; " ");
  [ .hook_event_name, .session_id, .cwd, .tool_name,
    ( .tool_input as $i | (.tool_name // "") as $t |
      if   $t == "Bash" then $i.command
      elif ($t | test("^(Edit|MultiEdit|Write|Read|NotebookEdit)$")) then ($i.file_path // $i.notebook_path)
      elif ($t == "Grep" or $t == "Glob") then $i.pattern
      elif $t == "WebFetch" then $i.url
      elif $t == "WebSearch" then $i.query
      elif ($t == "Task" or $t == "Agent") then $i.description
      else "" end ),
    .prompt, .message, .notification_type, .transcript_path ] | map(s) | join("\u001f")' 2>/dev/null)
[ -z "${SID:-}" ] && exit 0
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
  PreCompact)         state=dizzy;     detail="compacting context" ;;
  Stop)               state=done;      detail="finished" ;;
  SessionEnd)         rm -f "$F"; state=sleep ;;
  *)                  exit 0 ;;
esac
# Claude's own title for the conversation (what it puts on the pane) lives in the transcript
if [ -n "${TPATH:-}" ] && [ -r "$TPATH" ]; then
  t=$(grep -o '"aiTitle":"[^"]*"' "$TPATH" 2>/dev/null | tail -n 1)
  t=${t#'"aiTitle":"'}; t=${t%'"'}
  [ -n "$t" ] && topic="$t"
fi

# which terminal pane is this? kitty sets TERM=xterm-kitty; WezTerm's env can leak
# into kitty when it's launched from a WezTerm shell, so check kitty first.
if [ "${TERM:-}" = xterm-kitty ] && [ -n "${KITTY_WINDOW_ID:-}" ]; then PANE="k$KITTY_WINDOW_ID"
elif [ -n "${WEZTERM_PANE:-}" ]; then PANE="$WEZTERM_PANE"
else                                   # any other terminal: use the tty of our claude ancestor
  PANE=""; p=$PPID
  for _ in 1 2 3 4 5 6 7 8; do
    [ -z "$p" ] || [ "$p" -le 1 ] && break
    # match on the program itself: native `claude`, or npm's `node …/claude-code/cli.js`
    set -- $(ps -o args= -p "$p" 2>/dev/null)
    case "${1##*/}:${2:-}" in
      claude:*|node:*claude-code/cli.js)
        t=$(ps -o tty= -p "$p" 2>/dev/null | tr -d ' ')
        case "$t" in ''|'?'|'??') ;; *) PANE="t:$t"; break ;; esac ;;
    esac
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
  done
fi
now=$(date +%s)
if [ "$EV" != "SessionEnd" ]; then
  printf '%s%s%s%s%s%s%s%s%s%s%s%s%s\n' "$now" "$US" "$state" "$US" "$PANE" "$US" "$CWD" "$US" "$detail" "$US" "$topic" "$US" "${TPATH:-}" > "$F.tmp" 2>/dev/null \
    && mv -f "$F.tmp" "$F" 2>/dev/null
fi
printf '%s %s\n' "$now" "$state" > "$DIR/companion.state" 2>/dev/null || true
exit 0

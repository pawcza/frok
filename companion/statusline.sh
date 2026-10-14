#!/usr/bin/env bash
# statusline.sh — Claude Code's status line command. Claude Code pipes the
# session's status as JSON on stdin; we keep what the companion needs (context
# used, the 5-hour and 7-day usage limits) in $STATE/companion/status/<session>
#   <ts>\x1f<context %>\x1f<5h %>\x1f<5h resets at>\x1f<7d %>\x1f<7d resets at>\x1f<account>
# and print a short line for Claude Code's own status row.
set -u
DIR="${FROK_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/frok}/companion/status"
mkdir -p "$DIR" 2>/dev/null
IN="$(cat 2>/dev/null)"
US=$'\x1f'
IFS="$US" read -r SID MODEL CTX H5 H5R D7 D7R < <(printf '%s' "$IN" | jq -r '
  def n: if . == null then "" else (. | floor | tostring) end;
  [ .session_id // "", .model.display_name // "",
    (.context_window.used_percentage | n),
    (.rate_limits.five_hour.used_percentage | n), (.rate_limits.five_hour.resets_at | n),
    (.rate_limits.seven_day.used_percentage | n), (.rate_limits.seven_day.resets_at | n)
  ] | join("\u001f")' 2>/dev/null)
# which account: a ccs instance is its own config dir
ACCT=$(basename "${CLAUDE_CONFIG_DIR:-$HOME/.claude}")
if [ -n "${SID:-}" ]; then
  printf '%s%s%s%s%s%s%s%s%s%s%s%s%s\n' "$(date +%s)" "$US" "$CTX" "$US" "$H5" "$US" "$H5R" "$US" "$D7" "$US" "$D7R" "$US" "$ACCT" \
    > "$DIR/$SID.tmp" 2>/dev/null && mv -f "$DIR/$SID.tmp" "$DIR/$SID" 2>/dev/null
fi
out="${MODEL:-}"
[ -n "${CTX:-}" ] && out+="${out:+ · }ctx ${CTX}%"
[ -n "${H5:-}" ] && out+=" · 5h ${H5}%"
[ -n "${D7:-}" ] && out+=" · 7d ${D7}%"
printf '\033[2m%s\033[0m\n' "$out"
exit 0

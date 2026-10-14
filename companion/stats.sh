#!/usr/bin/env bash
# stats.sh — per-day Claude Code totals for the companion: tokens, lines
# added/removed by edits, and commits made. Reads every transcript in every
# Claude config, but only the bytes appended since the last run (offsets are
# remembered), so after the first pass a run takes a moment.
#   $STATE/companion/stats/days.json  {"2026-10-14": {tok, add, del, commits}, …}
set -u
DIR="${FROK_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/frok}/companion/stats"
mkdir -p "$DIR" || exit 0
DAYS="$DIR/days.json"; OFFS="$DIR/offsets"
LOCK="$DIR/lock"
mkdir "$LOCK" 2>/dev/null || { [ -n "$(find "$LOCK" -maxdepth 0 -mmin +30 2>/dev/null)" ] && rmdir "$LOCK" && mkdir "$LOCK"; } || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
[ -s "$DAYS" ] || echo '{}' > "$DAYS"
touch "$OFFS"

declare -A off
while IFS=$'\t' read -r o f; do [ -n "$f" ] && off[$f]=$o; done < "$OFFS"

dirs=()
[ -n "${CLAUDE_CONFIG_DIR:-}" ] && dirs+=("$CLAUDE_CONFIG_DIR/projects")
dirs+=("$HOME/.claude/projects" "$HOME"/.ccs/instances/*/projects)

chunks="$DIR/chunks.$$"; : > "$chunks"
newoffs="$DIR/offsets.$$"; : > "$newoffs"
while IFS= read -r -d '' f; do
  size=$(wc -c < "$f" 2>/dev/null) || continue; size=${size// /}   # wc, not stat: same on macOS and Linux
  o=${off[$f]:-0}; (( size < o )) && o=0          # rewritten: start over
  if (( size > o )); then
    # only whole lines: a transcript being written may end mid-line
    if [ "$(tail -c 1 "$f" | od -An -c | tr -d ' ')" = '\n' ]; then
      tail -c +$(( o + 1 )) "$f" | head -c $(( size - o )) >> "$chunks"
      o=$size
    fi
  fi
  printf '%s\t%s\n' "$o" "$f" >> "$newoffs"
done < <(find "${dirs[@]}" -name '*.jsonl' -mtime -40 -print0 2>/dev/null)

if [ -s "$chunks" ]; then
  jq -Rn --slurpfile old "$DAYS" --arg since "$(jq -rn 'now - 40 * 86400 | strftime("%Y-%m-%d")')" '
    def day: (.timestamp // "") | if . == "" then null
      else (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 | localtime | strftime("%Y-%m-%d")) end;
    reduce (inputs | fromjson? | select(type == "object")) as $r ({d: $old[0], last: "", git: {}};
      ($r | day) as $k
      | if $k == null then .
        elif $r.type == "assistant" and $r.message.usage != null then
          # a `git commit` call counts once its result comes back without an error
          reduce ($r.message.content[]? | select(.type == "tool_use" and .name == "Bash"
                    and ((.input.command // "") | test("\\bgit\\s+(-C\\s+\\S+\\s+)?commit\\b")))) as $u (.; .git[$u.id] = true)
          # one API response is written as several records sharing its id
          | if $r.message.id == .last then . else
            .last = $r.message.id
            | .d[$k].tok += ($r.message.usage | (.input_tokens // 0) + (.cache_creation_input_tokens // 0)
                                               + (.cache_read_input_tokens // 0) + (.output_tokens // 0))
          end
        elif $r.type == "user" and ($r.toolUseResult | type) == "object" then
          reduce ($r.message.content[]? | select(type == "object" and .type == "tool_result")) as $c (.;
            if .git[$c.tool_use_id] then del(.git[$c.tool_use_id]) | if $c.is_error == true then . else .d[$k].commits += 1 end else . end)
          | $r.toolUseResult as $t
          | if ($t.structuredPatch | type) == "array" and ($t.structuredPatch | length) > 0 then
              .d[$k].add += ([$t.structuredPatch[].lines[]? | select(startswith("+"))] | length)
              | .d[$k].del += ([$t.structuredPatch[].lines[]? | select(startswith("-"))] | length)
            elif $t.type == "create" and ($t.content | type) == "string" then
              .d[$k].add += ($t.content | rtrimstr("\n") | split("\n") | length)
            else . end
        else . end)
    | .d | with_entries(select(.key >= $since))' < "$chunks" > "$DAYS.tmp" && mv -f "$DAYS.tmp" "$DAYS" \
    || { rm -f "$chunks" "$newoffs" "$DAYS.tmp"; exit 0; }     # keep the old offsets: retry next run
fi
mv -f "$newoffs" "$OFFS"
rm -f "$chunks"

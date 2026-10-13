#!/usr/bin/env bash
# install.sh — set up the frog companion for Claude Code (macOS, Linux, WSL).
#
#   ./install.sh               install / update
#   ./install.sh --uninstall   remove the hooks and the `companion` command
#
# Env overrides:
#   FROG_HOME        where the scripts live      (default ~/.config/terminal)
#   CLAUDE_SETTINGS  which settings.json to hook (default $CLAUDE_CONFIG_DIR or ~/.claude)
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${FROG_HOME:-$HOME/.config/terminal}"
SETTINGS="${CLAUDE_SETTINGS:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json}"
BIN="$HOME/.local/bin"
HOOK="$DEST/companion-event.sh"
EVENTS='["SessionStart","SessionEnd","UserPromptSubmit","PreToolUse","PostToolUse","PostToolUseFailure","PermissionRequest","Notification","SubagentStart","SubagentStop","PreCompact","Stop"]'

say() { printf '\033[32m✓\033[0m %s\n' "$*"; }
die() { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

backup_settings() { [ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.bak.frog-$(date +%Y%m%d%H%M%S)"; }

if [ "${1:-}" = "--uninstall" ]; then
  command -v jq >/dev/null || die "jq is needed to edit $SETTINGS"
  if [ -f "$SETTINGS" ]; then
    backup_settings
    jq --arg cmd "$HOOK" '
      if .hooks then .hooks |= (with_entries(
        .value |= (map(.hooks |= map(select(.command != $cmd))) | map(select((.hooks | length) > 0))))
        | with_entries(select((.value | length) > 0))) else . end' "$SETTINGS" > "$SETTINGS.tmp"
    mv "$SETTINGS.tmp" "$SETTINGS"; say "removed the hooks from $SETTINGS"
  fi
  rm -f "$BIN/companion"; say "removed $BIN/companion"
  echo "  (scripts left in $DEST; delete that folder if you don't want them)"
  exit 0
fi

# ── dependencies ──────────────────────────────────────────────────────
missing=()
for c in zsh jq curl fold; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
if [ ${#missing[@]} -gt 0 ]; then
  echo "Missing: ${missing[*]}"
  if command -v brew >/dev/null; then echo "  brew install ${missing[*]}"
  elif command -v apt-get >/dev/null; then echo "  sudo apt install ${missing[*]}"
  elif command -v dnf >/dev/null; then echo "  sudo dnf install ${missing[*]}"; fi
  exit 1
fi

# ── files ─────────────────────────────────────────────────────────────
mkdir -p "$DEST/sessions" "$BIN"
install -m 0755 "$SRC/claude-companion.sh" "$DEST/claude-companion.sh"
install -m 0755 "$SRC/companion-event.sh"  "$DEST/companion-event.sh"
install -m 0644 "$SRC/frog.txt"            "$DEST/frog.txt"
ln -sf "$DEST/claude-companion.sh" "$BIN/companion"
say "installed into $DEST"
say "linked the \`companion\` command into $BIN"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "  note: add $BIN to your PATH to run \`companion\`" ;; esac

# ── Claude Code hooks (added alongside any you already have) ──────────
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
backup_settings
jq --arg cmd "$HOOK" --argjson evs "$EVENTS" '
  .hooks //= {} |
  reduce $evs[] as $e (.;
    if ([.hooks[$e][]?.hooks[]?.command] | index($cmd)) then .
    else .hooks[$e] = ((.hooks[$e] // []) + [{"matcher": "", "hooks": [{"type": "command", "command": $cmd, "timeout": 5, "async": true}]}])
    end)' "$SETTINGS" > "$SETTINGS.tmp"
mv "$SETTINGS.tmp" "$SETTINGS"
say "hooked $(jq -r --arg cmd "$HOOK" '[.hooks[] | select(any(.[]; any(.hooks[]?; .command == $cmd)))] | length' "$SETTINGS") Claude Code events in $SETTINGS"

echo
echo "Run \`companion\` in a terminal pane. Sessions started before this show up once they do something."

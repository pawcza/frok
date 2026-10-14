# core.zsh — paths, output, config, and package installs shared by every module.

FROK_CONFIG_DIR=${FROK_CONFIG_DIR:-$HOME/.config/frok}
FROK_STATE=${FROK_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/frok}
FROK_CFG=$FROK_CONFIG_DIR/frok.json
FROK_GEN=$FROK_CONFIG_DIR/generated          # files frok writes and other configs include
mkdir -p $FROK_CONFIG_DIR $FROK_STATE/companion/sessions $FROK_GEN
# direct installs land in ~/.local/bin, which a fresh shell may not have on PATH yet
(( ${path[(Ie)$HOME/.local/bin]} )) || path=($HOME/.local/bin $path)

# FROK_INDENT lines these up with the setup screens
say()  { print -P "${FROK_INDENT-}%F{green}✓%f $*"; }
step() { print -P "${FROK_INDENT-}%F{cyan}→%f $*"; }
warn() { print -P "${FROK_INDENT-}%F{yellow}!%f $*" >&2; }
die()  { print -P "${FROK_INDENT-}%F{red}✗%f $*" >&2; exit 1; }
has()  { (( $+commands[$1] )); }

frok_os() {
  case $OSTYPE in
    darwin*) print macos ;;
    # a WSL kernel alone isn't enough: Docker containers on Windows share it but can't reach Windows
    linux*)  if [[ -n $WSL_DISTRO_NAME || -e /usr/bin/wslpath ]] && grep -qi microsoft /proc/version 2>/dev/null; then print wsl; else print linux; fi ;;
    *)       print other ;;
  esac
}
OS=$(frok_os)

# ── config (one JSON file; every setting has a default) ─────────────
FROK_DEFAULTS='{
  "theme": "tokyo-night",
  "background": "rain",
  "background_opacity": 0.2,
  "companion": "frok",
  "facts": true,
  "layout": "side",
  "layout_on_start": true,
  "agent": "claude",
  "workdir": "~",
  "prompt": "starship",
  "font": { "family": "CaskaydiaCove Nerd Font", "size": 11 },
  "tools": ["eza","bat","fd","zoxide","ripgrep","fzf","delta","lazygit","gh","btop","tldr","autosuggestions"],
  "terminals": []
}'

cfg_init() {
  if [[ -f $FROK_CFG ]]; then
    [[ $(jq -r '.companion // empty' $FROK_CFG) == frog ]] && cfg_set .companion '"frok"'   # renamed after its tool
    return 0
  fi
  print -r -- $FROK_DEFAULTS | jq . >| $FROK_CFG
  [[ $OS == macos ]] && cfg_set .font.size 14     # Retina: the MacBook setup's size
  return 0
}
# cfg <jq path>  → raw value (defaults filled in)
cfg() { jq -r --argjson d "$FROK_DEFAULTS" "(\$d * .) | $1 | select(. != null)" $FROK_CFG 2>/dev/null; }
# cfg_set <jq path> <json value>
cfg_set() {
  local tmp=$FROK_CFG.tmp
  jq --argjson v "$2" "$1 = \$v" $FROK_CFG >| $tmp && mv -f $tmp $FROK_CFG
}
# a string value as JSON
jstr() { jq -Rn --arg s "$1" '$s'; }

expand_home() { print -r -- ${1/#\~/$HOME}; }

# ── Windows side, from WSL ──────────────────────────────────────────
win_env() {   # win_env LOCALAPPDATA → its value as a WSL path
  local v; v=$(cd /mnt/c 2>/dev/null && cmd.exe /c "echo %$1%" 2>/dev/null | tr -d '\r')
  [[ -n $v && $v != %*% ]] && wslpath -u "$v"
}

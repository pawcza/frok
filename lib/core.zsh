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

# ── package installs ────────────────────────────────────────────────
as_root() {
  if (( EUID == 0 )); then "$@"
  elif has sudo; then sudo "$@"
  else die "need root for: $* (no sudo)"; fi
}

frok_pm() {
  if [[ $OS == macos ]]; then has brew && print brew; return; fi
  local m; for m in apt-get dnf pacman zypper apk brew; do has $m && { print ${m%-get}; return }; done
}
PM=$(frok_pm)

# Package name for a tool on this package manager ("-" = not packaged there).
pkg_name() {
  local t=$1
  case "$PM:$t" in
    apt:fd) print fd-find ;;           apt:delta) print git-delta ;;
    apt:lazygit|apt:starship) print -r -- - ;;
    apt:autosuggestions) print zsh-autosuggestions ;;
    brew:autosuggestions) print zsh-autosuggestions ;;
    brew:tldr) print tlrc ;;           brew:delta) print git-delta ;;
    dnf:delta) print git-delta ;;      dnf:fd) print fd-find ;;
    pacman:delta) print git-delta ;;   pacman:autosuggestions) print zsh-autosuggestions ;;
    dnf:autosuggestions) print zsh-autosuggestions ;;
    *:pillow) case $PM in apt) print python3-pil ;; brew) print pillow ;; dnf) print python3-pillow ;; pacman) print python-pillow ;; *) print py3-pillow ;; esac ;;
    *) print $t ;;
  esac
}

# Is a tool already there? (Debian renames some binaries.)
tool_present() {
  case $1 in
    fd)      has fd || has fdfind ;;
    bat)     has bat || has batcat ;;
    ripgrep) has rg ;;
    tldr)    has tldr || has tlrc ;;
    autosuggestions) [[ -n $(autosuggest_path) ]] ;;
    pillow)  python3 -c 'import PIL' 2>/dev/null ;;
    *)       has $1 ;;
  esac
}

autosuggest_path() {
  local p
  for p in /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
           /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
           /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
           /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh; do
    [[ -r $p ]] && { print $p; return }
  done
}

typeset -g _pm_updated=0
FROK_LOG=$FROK_STATE/install.log

# quietly <what> <command…> — runs it with its output in the install log; shows one line
quietly() {
  local what=$1; shift
  [[ -t 1 ]] && print -Pn "${FROK_INDENT-}%F{cyan}…%f $what"
  if "$@" >>$FROK_LOG 2>&1; then
    [[ -t 1 ]] && print -n $'\r\e[K'; say $what
  else
    [[ -t 1 ]] && print -n $'\r\e[K'; warn "$what failed (details in ${FROK_LOG/#$HOME/~})"; return 1
  fi
}

pm_install() {
  case $PM in
    brew)   brew install "$@" ;;
    apt)    (( _pm_updated++ )) || as_root apt-get update -qq; as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf)    as_root dnf install -y "$@" ;;
    pacman) as_root pacman -S --needed --noconfirm "$@" ;;
    zypper) as_root zypper install -y "$@" ;;
    apk)    as_root apk add "$@" ;;
  esac
}

# pkg_install <tool...>  — installs whatever is missing, one package-manager call.
pkg_install() {
  local t n; local -a names fallback
  for t in "$@"; do
    tool_present $t && continue
    n=$(pkg_name $t)
    if [[ $n == - || -z $PM ]]; then fallback+=($t); else names+=($n); fi
  done
  if (( $#names )); then
    # one unknown name fails the whole batch on most package managers: then go one by one
    quietly "installing ${(j:, :)names}" pm_install $names 2>/dev/null ||
      { local n1; for n1 in $names; do quietly "installing $n1" pm_install $n1; done }
  fi
  for t in $fallback; do install_direct $t; done
  rehash
}

# Tools a distro doesn't package: their own installers / release binaries.
install_direct() {
  mkdir -p $HOME/.local/bin
  case $1 in
    starship) quietly "installing starship" starship_get ;;
    lazygit)  quietly "installing lazygit" lazygit_get ;;
    *) warn "don't know how to install $1 here" ;;
  esac
}
starship_get() { curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b $HOME/.local/bin; }
lazygit_get() {
  local arch=x86_64; [[ $(uname -m) == (aarch64|arm64) ]] && arch=arm64
  local tag=$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r .tag_name)
  [[ -n $tag && $tag != null ]] || { print "couldn't look up lazygit's latest release"; return 1 }
  curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/$tag/lazygit_${tag#v}_Linux_${arch}.tar.gz" \
    | tar -xz -C $HOME/.local/bin lazygit
}

# ── Windows side, from WSL ──────────────────────────────────────────
win_env() {   # win_env LOCALAPPDATA → its value as a WSL path
  local v; v=$(cd /mnt/c 2>/dev/null && cmd.exe /c "echo %$1%" 2>/dev/null | tr -d '\r')
  [[ -n $v && $v != %*% ]] && wslpath -u "$v"
}

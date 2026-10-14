# core.zsh — paths, output, config, and package installs shared by every module.

FROK_CONFIG_DIR=${FROK_CONFIG_DIR:-$HOME/.config/frok}
FROK_STATE=${FROK_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/frok}
FROK_CFG=$FROK_CONFIG_DIR/frok.json
FROK_GEN=$FROK_CONFIG_DIR/generated          # files frok writes and other configs include
mkdir -p $FROK_CONFIG_DIR $FROK_STATE/companion/sessions $FROK_GEN

say()  { print -P "%F{green}✓%f $*"; }
step() { print -P "%F{cyan}→%f $*"; }
warn() { print -P "%F{yellow}!%f $*" >&2; }
die()  { print -P "%F{red}✗%f $*" >&2; exit 1; }
has()  { (( $+commands[$1] )); }

frok_os() {
  case $OSTYPE in
    darwin*) print macos ;;
    linux*)  if [[ -n $WSL_DISTRO_NAME ]] || grep -qi microsoft /proc/version 2>/dev/null; then print wsl; else print linux; fi ;;
    *)       print other ;;
  esac
}
OS=$(frok_os)

# ── config (one JSON file; every setting has a default) ─────────────
FROK_DEFAULTS='{
  "theme": "tokyo-night",
  "background": "rain",
  "background_opacity": 0.2,
  "companion": "frog",
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
  [[ -f $FROK_CFG ]] && return
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
    apt:lazygit|apt:starship) print - ;;
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
# pkg_install <tool...>  — installs whatever is missing, one package-manager call.
pkg_install() {
  local t n; local -a names fallback
  for t in "$@"; do
    tool_present $t && continue
    n=$(pkg_name $t)
    if [[ $n == - || -z $PM ]]; then fallback+=($t); else names+=($n); fi
  done
  if (( $#names )); then
    step "installing ${(j:, :)names}"
    case $PM in
      brew)   brew install $names ;;
      apt)    (( _pm_updated++ )) || as_root apt-get update -qq; as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y $names ;;
      dnf)    as_root dnf install -y $names ;;
      pacman) as_root pacman -S --needed --noconfirm $names ;;
      zypper) as_root zypper install -y $names ;;
      apk)    as_root apk add $names ;;
    esac || {
      # one unknown name fails the whole batch on most package managers: go one by one
      local n1; for n1 in $names; do
        case $PM in
          brew) brew install $n1 ;;  apt) as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y $n1 ;;  dnf) as_root dnf install -y $n1 ;;
          pacman) as_root pacman -S --needed --noconfirm $n1 ;;  zypper) as_root zypper install -y $n1 ;;  apk) as_root apk add $n1 ;;
        esac >/dev/null 2>&1 || warn "couldn't install $n1 with $PM"
      done
    }
  fi
  for t in $fallback; do install_direct $t; done
}

# Tools a distro doesn't package: their own installers / release binaries.
install_direct() {
  mkdir -p $HOME/.local/bin
  case $1 in
    starship)
      step "installing starship"
      curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b $HOME/.local/bin >/dev/null ;;
    lazygit)
      step "installing lazygit"
      local arch=x86_64; [[ $(uname -m) == (aarch64|arm64) ]] && arch=arm64
      local tag=$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r .tag_name)
      [[ -n $tag ]] || { warn "couldn't look up lazygit's latest release"; return }
      curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/$tag/lazygit_${tag#v}_Linux_${arch}.tar.gz" \
        | tar -xz -C $HOME/.local/bin lazygit ;;
    *) warn "don't know how to install $1 here" ;;
  esac
}

# ── Windows side, from WSL ──────────────────────────────────────────
win_env() {   # win_env LOCALAPPDATA → its value as a WSL path
  local v; v=$(cd /mnt/c 2>/dev/null && cmd.exe /c "echo %$1%" 2>/dev/null | tr -d '\r')
  [[ -n $v && $v != %*% ]] && wslpath -u "$v"
}

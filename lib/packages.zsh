# packages.zsh — installing things: the system package manager, direct
# downloads for what it lacks, and the optional CLI tools.

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


# ── CLI tools ─────────────────────────────────────────────────────────
tools_install() {
  local -a t; t=(${(f)"$(cfg '.tools[]?')"})
  [[ $(cfg .prompt) == starship ]] && t+=(starship)
  (( $#t )) && pkg_install $t
  # git-delta as git's pager, unless you already chose one
  if has delta && [[ -z $(git config --global core.pager) ]]; then
    git config --global core.pager delta
    git config --global interactive.diffFilter 'delta --color-only'
    say "git now pages through delta"
  fi
}

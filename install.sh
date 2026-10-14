#!/bin/sh
# frok bootstrap — gets a bare machine to the point where `frok` runs, then
# starts the guided setup. Everything else (fonts, CLI tools, prompt,
# backgrounds, companion hooks) is installed by frok itself as you pick it.
#
#   git clone https://github.com/pawcza/frok && ./frok/install.sh
#   curl -fsSL https://raw.githubusercontent.com/pawcza/frok/main/install.sh | sh
#
# Env overrides:
#   FROK_HOME   where frok lives        (default: this clone, else ~/.local/share/frok)
#   FROK_REPO   what to clone            (default: https://github.com/pawcza/frok.git)
#   FROK_NO_SETUP=1   install only, don't start the setup
set -eu

REPO=${FROK_REPO:-https://github.com/pawcza/frok.git}
BIN="$HOME/.local/bin"

say()  { printf '\033[32m✓\033[0m %s\n' "$*"; }
step() { printf '\033[36m→\033[0m %s\n' "$*"; }
die()  { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }

as_root() {
  if [ "$(id -u)" = 0 ]; then "$@"
  elif has sudo; then sudo "$@"
  else die "need root to run: $* (no sudo found)"; fi
}

# ── which system ──────────────────────────────────────────────────────
case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux)  if grep -qi microsoft /proc/version 2>/dev/null; then OS=wsl; else OS=linux; fi ;;
  MINGW*|MSYS*|CYGWIN*)
    die "frok runs inside WSL on Windows. Install it with \`wsl --install\`, open Ubuntu, and run this again there." ;;
  *) die "unsupported system: $(uname -s)" ;;
esac
step "system: $OS"

# ── frok's own needs: git curl jq zsh unzip ───────────────────────────
need=""
for c in git curl jq zsh unzip; do has "$c" || need="$need $c"; done
if [ -n "$need" ]; then
  step "installing:$need"
  if [ "$OS" = macos ]; then
    if ! has brew; then
      step "installing Homebrew (it asks for your password)"
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty
      [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
      [ -x /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)"
    fi
    # shellcheck disable=SC2086
    brew install $need
  elif has apt-get; then as_root apt-get update -qq && as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y $need
  elif has dnf;     then as_root dnf install -y $need
  elif has pacman;  then as_root pacman -S --needed --noconfirm $need
  elif has zypper;  then as_root zypper install -y $need
  elif has apk;     then as_root apk add $need
  else die "no package manager I know; install:$need"; fi
fi
for c in git curl jq zsh unzip; do has "$c" || die "$c still missing"; done
say "git, curl, jq, zsh, unzip"

# ── frok itself ───────────────────────────────────────────────────────
HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)
if [ -n "${FROK_HOME:-}" ]; then :
elif [ -n "$HERE" ] && [ -f "$HERE/bin/frok" ]; then FROK_HOME=$HERE      # running from a clone
else FROK_HOME="$HOME/.local/share/frok"; fi
if [ ! -f "$FROK_HOME/bin/frok" ]; then
  step "cloning frok into $FROK_HOME"
  git clone -q "$REPO" "$FROK_HOME"
fi
mkdir -p "$BIN"
ln -sf "$FROK_HOME/bin/frok" "$BIN/frok"
say "frok → $BIN/frok"

# ~/.local/bin on PATH for every shell frok may configure
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [ -f "$rc" ] || [ "$rc" = "$HOME/.zshrc" ] || continue
  grep -qs 'HOME/.local/bin' "$rc" || printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
done

[ "${FROK_NO_SETUP:-}" = 1 ] && { say "installed. Run \`frok\` to set up."; exit 0; }
step "starting setup"
if [ -t 0 ]; then exec "$FROK_HOME/bin/frok" setup
else exec "$FROK_HOME/bin/frok" setup </dev/tty; fi

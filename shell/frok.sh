# frok shell layer — sourced by ONE line at the end of ~/.zshrc / ~/.bashrc:
#   [ -r ~/.config/frok/generated/init.sh ] && . ~/.config/frok/generated/init.sh
# Works in zsh and bash. Theme colours and module switches come from
# generated/env.sh, which `frok` rewrites whenever you change a setting.

[ -r "$HOME/.config/frok/generated/env.sh" ] && . "$HOME/.config/frok/generated/env.sh"
_frok_has() { command -v "$1" >/dev/null 2>&1; }
if [ -n "${ZSH_VERSION:-}" ]; then _frok_sh=zsh; else _frok_sh=bash; fi

# ── Drop Claude Code session markers inherited by accident ────────────
# Claude Code exports CLAUDECODE / CLAUDE_CODE_CHILD_SESSION / CLAUDE_PID … to
# the processes it starts. If the terminal itself was launched from inside a
# Claude session, every pane inherits them and each new `claude` thinks it's a
# child ("Transcript saving is off – inherited CLAUDE_CODE_CHILD_SESSION").
# Keep them only when that Claude process really is one of our ancestors.
_frok_cc_is_ancestor() {
  _p=$$
  while [ -n "$_p" ] && [ "$_p" -gt 1 ]; do
    [ "$_p" = "$1" ] && return 0
    _p=$(ps -o ppid= -p "$_p" 2>/dev/null | tr -d ' ')
  done
  return 1
}
case $- in *i*)
  if [ -n "${CLAUDECODE:-}${CLAUDE_CODE_CHILD_SESSION:-}${CLAUDE_PID:-}" ] && \
     ! { [ -n "${CLAUDE_PID:-}" ] && _frok_cc_is_ancestor "$CLAUDE_PID"; }; then
    unset CLAUDECODE CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH \
          CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN CLAUDE_CODE_SESSION_ATTENDED \
          CLAUDE_CODE_SESSION_ID CLAUDE_PID CLAUDE_EFFORT CLAUDE_CONFIG_DIR AI_AGENT
  fi ;;
esac
unset -f _frok_cc_is_ancestor; unset _p

# ── eza (better ls) ───────────────────────────────────────────────────
if _frok_has eza; then
  alias ls='eza --icons --group-directories-first'
  alias ll='eza -l --icons --group-directories-first --git'
  alias la='eza -la --icons --group-directories-first --git'
  alias lt='eza --tree --level=2 --icons'
fi

# ── bat (better cat; Debian calls it batcat) ──────────────────────────
if _frok_has bat; then alias cat='bat --style=plain --paging=never'
elif _frok_has batcat; then alias cat='batcat --style=plain --paging=never'; alias bat=batcat; fi

# ── fd (Debian: fdfind) / lazygit ─────────────────────────────────────
_frok_has fd || { _frok_has fdfind && alias fd=fdfind; }
_frok_has lazygit && alias lg='lazygit'

# ── zoxide (smart cd: use `z <dir>`) ──────────────────────────────────
_frok_has zoxide && eval "$(zoxide init $_frok_sh)"

# ── fzf (Ctrl+R history, Ctrl+T files, Alt+C cd) ──────────────────────
if _frok_has fzf; then
  if fzf --$_frok_sh >/dev/null 2>&1; then eval "$(fzf --$_frok_sh)"         # fzf ≥ 0.48
  else                                                                        # older distro fzf
    for _f in /usr/share/doc/fzf/examples/key-bindings.$_frok_sh /usr/share/fzf/key-bindings.$_frok_sh \
              /usr/share/doc/fzf/examples/completion.$_frok_sh /usr/share/fzf/completion.$_frok_sh; do
      [ -r "$_f" ] && . "$_f"
    done; unset _f
  fi
  if _frok_has fd; then export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
  elif _frok_has fdfind; then export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --exclude .git'; fi
fi

# ── WezTerm shell integration: feed cwd + git branch to the status bar ─
if [ -n "${WEZTERM_PANE:-}" ] && [ "${TERM:-}" != xterm-kitty ]; then
  _frok_wz() {
    printf '\033]7;file://%s%s\033\\' "${HOSTNAME:-${HOST:-}}" "$PWD"
    printf '\033]1337;SetUserVar=WEZTERM_GIT=%s\007' \
      "$(git symbolic-ref --short HEAD 2>/dev/null | base64 | tr -d '\n')"
  }
  if [ $_frok_sh = zsh ]; then autoload -Uz add-zsh-hook; add-zsh-hook precmd _frok_wz
  else PROMPT_COMMAND="_frok_wz${PROMPT_COMMAND:+;$PROMPT_COMMAND}"; fi
fi

# ── Inline command suggestions (zsh: grey, from history + completions) ─
# → accepts the whole suggestion, Alt/⌥→ accepts one word.
if [ $_frok_sh = zsh ] && [ -n "${FROK_AUTOSUGGEST:-}" ] && [ -r "$FROK_AUTOSUGGEST" ]; then
  ZSH_AUTOSUGGEST_STRATEGY=(history completion)
  ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=200
  . "$FROK_AUTOSUGGEST"
  bindkey '^[[1;3C' forward-word
fi

# ── Prompt ────────────────────────────────────────────────────────────
if [ "${FROK_PROMPT:-}" = starship ] && _frok_has starship; then
  export STARSHIP_CONFIG="$HOME/.config/frok/generated/starship.toml"
  eval "$(starship init $_frok_sh)"
fi

unset _frok_sh

# ~/.config/terminal/claude-terminal.zsh
# Modern CLI tooling, WezTerm status-bar integration, prompt, and companion.
# Sourced at the end of ~/.zshrc. Remove that source line to fully disable.

# ── Drop Claude Code session markers inherited by accident ────────────
# Claude Code exports CLAUDECODE / CLAUDE_CODE_CHILD_SESSION / CLAUDE_PID … to
# the processes it starts. If WezTerm itself was launched from inside a Claude
# session, every pane inherits them and each new `claude` thinks it's a child
# ("Transcript saving is off – inherited CLAUDE_CODE_CHILD_SESSION marker").
# Keep them only when that Claude process really is one of our ancestors.
_cc_is_ancestor() {
  local p=$$ target=$1
  while [[ -n $p && $p -gt 1 ]]; do
    [[ $p == $target ]] && return 0
    p=$(ps -o ppid= -p $p 2>/dev/null); p=${p// /}
  done
  return 1
}
if [[ -o interactive ]] && [[ -n $CLAUDECODE$CLAUDE_CODE_CHILD_SESSION$CLAUDE_PID ]] && \
   ! { [[ -n $CLAUDE_PID ]] && _cc_is_ancestor $CLAUDE_PID; }; then
  unset CLAUDECODE CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH \
        CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN CLAUDE_CODE_SESSION_ATTENDED \
        CLAUDE_CODE_SESSION_ID CLAUDE_PID CLAUDE_EFFORT CLAUDE_CONFIG_DIR AI_AGENT
fi
unfunction _cc_is_ancestor

# ── eza (better ls) ───────────────────────────────────────────────────
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --icons --group-directories-first'
  alias ll='eza -l --icons --group-directories-first --git'
  alias la='eza -la --icons --group-directories-first --git'
  alias lt='eza --tree --level=2 --icons'
fi

# ── bat (better cat) ──────────────────────────────────────────────────
if command -v bat >/dev/null 2>&1; then
  alias cat='bat --style=plain --paging=never'
  export BAT_THEME="base16"
fi

# ── fd / ripgrep / lazygit ────────────────────────────────────────────
command -v lazygit >/dev/null 2>&1 && alias lg='lazygit'

# ── zoxide (smart cd: use `z <dir>`) ──────────────────────────────────
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"

# ── fzf (Ctrl+R history, Ctrl+T files, Alt+C cd) ──────────────────────
if command -v fzf >/dev/null 2>&1; then
  eval "$(fzf --zsh)" 2>/dev/null
  command -v fd >/dev/null 2>&1 && export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
  export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border \
    --color=fg:#c0caf5,hl:#7aa2f7,fg+:#c0caf5,hl+:#7dcfff,bg+:#283457,pointer:#bb9af7,marker:#9ece6a,border:#3b4261,prompt:#7aa2f7,info:#565f89"
fi

# ── WezTerm shell integration: feed cwd + git branch to the status bar ─
if [[ -n "$WEZTERM_PANE" && "$TERM" != xterm-kitty ]]; then
  autoload -Uz add-zsh-hook
  _wz_osc7() { printf '\033]7;file://%s%s\033\\' "${HOST}" "${PWD}"; }
  _wz_git() {
    local b; b="$(git symbolic-ref --short HEAD 2>/dev/null)"
    printf '\033]1337;SetUserVar=WEZTERM_GIT=%s\007' "$(printf '%s' "$b" | base64 | tr -d '\n')"
  }
  add-zsh-hook precmd _wz_osc7
  add-zsh-hook precmd _wz_git
fi

# ── Inline command suggestions (grey, from history + completions) ─────
# → accepts the whole suggestion, ⌥→ accepts one word.
if [[ -r /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  ZSH_AUTOSUGGEST_STRATEGY=(history completion)
  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#565f89'          # Tokyo Night comment grey
  ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=200
  source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  bindkey '^[[1;3C' forward-word                       # ⌥→ (WezTerm sends this) = accept one word
fi

# ── Starship prompt (richer than the basic vcs_info prompt above) ─────
command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"

# ── Companion: the animated pet lives in its own pane ─────────────────
# `companion` runs it (pet + tips + hotkeys); it reacts to every Claude
# session via the hooks. No greeting in other panes.
alias companion='~/.config/terminal/claude-companion.sh'

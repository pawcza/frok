# commands.zsh — what the frok subcommands do: setup, apply, status, doctor,
# uninstall, and the help text.

usage() {
  cat <<EOF
frok — terminal setup and settings

  frok                      the companion in this pane (first run: the setup)
  frok menu                 every setting and what frok can do (also , in the companion)
  frok setup                step-by-step setup
  frok status [--json]      what's set and what's available
  frok apply                re-apply everything
  frok doctor               check the install

  frok theme [name]                         colour theme (no name: list with swatches)
  frok background <effect>|none|<file>      animated, recoloured per theme: rain starfield snow aurora synthwave
  frok background opacity <0-1>
  frok companion <pet>|none                 the Claude Code session pet (frok cat ghost robot octopus)
  frok companion facts on|off               useless facts in the companion
  frok dashboard [add|remove|move|set|reset] the widgets under the sessions (no args: list)
  frok layout [name]                        pane layout (no name: list)
  frok layout open                          open the layout now (Windows Terminal)
  frok layout autostart on|off              build it when the terminal starts
  frok agent "<command>"                    what agent panes run (default: claude)
  frok workdir <dir>                        where layout panes start
  frok prompt starship|none
  frok font "<family>" [size] | frok font size <n>
  frok tools [install | add <t> | remove <t>]
  frok terminals [set <names…> | auto]
  frok shell zsh|bash [--force]             change your login shell (checks the new one gets your PATH/aliases)
  frok shell port                           rebuild ~/.zshrc from ~/.bashrc (old one backed up)
  frok update                               pull the latest frok and re-apply
  frok uninstall                            undo frok's changes (keeps ~/.config/frok)
EOF
}

# ── apply ─────────────────────────────────────────────────────────────
apply_all() {
  cfg_init
  load_theme $(cfg .theme)
  render_keys
  [[ $(cfg .prompt) == starship ]] && pkg_install starship
  render_shell
  render_starship
  font_install
  companion_hooks $(cfg .companion)
  skill_install
  render_terminals
  cfg_set .configured true
  say "applied (${T[name]})"
}

on_off() { case $1 in on|true|yes) print true ;; off|false|no) print false ;; *) die "on or off?" ;; esac; }

# ── picker for questions asked before the wizard ──────────────────────
pick() {   # pick "<question>" <default> <options…> → chosen option
  local q=$1 def=$2 o; shift 2
  local -a opts=(); for o; do opts+=($o ""); done
  (( $#T )) || load_theme $(cfg .theme)
  print -r -- $'\n'"  $WZ_B$q$WZ_R"$'\n' >&2
  wz_choose $def "${opts[@]}"
}

# Everything that may need a password happens here, before the screens start.
prepare() {
  # what agent splits run, asked on the first setup when there's more than one way to start Claude
  if [[ $(cfg .configured) != true && $(cfg .agent) == claude ]]; then
    local -a cc; cc=(${(f)"$(claude_choices)"})
    (( $#cc > 1 )) && cfg_set .agent "$(jstr "$(pick 'What should agent splits run?' ${cc[1]} $cc)")"
  fi
  if (( EUID )) && has sudo && ! sudo -n true 2>/dev/null; then
    step "frok installs packages with sudo: enter your password once"
    sudo -v </dev/tty || die "sudo is needed to install packages"
  fi
  tools_install
  pkg_install starship python3 pillow
  font_install
  if [[ ${SHELL:t} != zsh ]] && [[ $(pick 'Make zsh your login shell? (the companion and layouts use it either way)' yes yes no) == yes ]]; then
    shell_set zsh
  fi
}

setup() {
  cfg_init
  { : </dev/tty } 2>/dev/null || die "setup asks questions, so it needs a terminal: run \`frok setup\` in a terminal window"
  wz_welcome
  wz_ready
  prepare
  wizard
}

# ── status ────────────────────────────────────────────────────────────
status_json() {
  cfg_init
  jq -n --argjson cfg "$(jq --argjson d "$FROK_DEFAULTS" '$d * .' $FROK_CFG)" \
     --arg os $OS --arg pm "$PM" --arg home $FROK_HOME --arg shell ${SHELL:t} \
     --argjson det "$(terminals_detected | jq -R . | jq -s .)" \
     --argjson act "$(terminals_active | jq -R . | jq -s .)" \
     --argjson themes "$(theme_names | jq -R . | jq -s .)" \
     --argjson layouts "$(for l in $(layout_names); do jq -c '{name, about}' $(layout_file $l); done | jq -s .)" \
     --argjson comps "$(companion_names | jq -R . | jq -s .)" \
     --argjson bgs "$(bg_effects | jq -R . | jq -s .)" \
     --argjson widgets "$(widget_names | jq -R . | jq -s .)" \
     --argjson claude "$(has claude && print true || print false)" '
    {configured: ($cfg.configured // false), os:$os, package_manager:$pm, frok_home:$home, login_shell:$shell,
     claude_code:$claude, terminals:{detected:$det, configured:$act}, settings:($cfg | del(.configured)),
     available:{themes:$themes, layouts:$layouts, companions:($comps + ["none"]), widgets:$widgets, backgrounds:($bgs + ["none","<path to image/gif>"]),
       prompts:["starship","none"], fonts:["CaskaydiaCove Nerd Font","JetBrainsMono Nerd Font","FiraCode Nerd Font","Hack Nerd Font","MesloLGS Nerd Font","<any installed font>"],
       tools:["eza","bat","fd","zoxide","ripgrep","fzf","delta","lazygit","gh","btop","tldr","autosuggestions"]}}'
}

status() {
  [[ $1 == --json ]] && { status_json; return }
  cfg_init; load_theme $(cfg .theme)
  print -P "%Bfrok%b on $OS ($PM) · $FROK_HOME"
  printf '  %-12s %s  %s\n' theme $(cfg .theme) "$(swatch)"
  printf '  %-12s %s (opacity %s)\n' background $(cfg .background) $(cfg .background_opacity)
  printf '  %-12s %s (facts %s)\n' companion $(cfg .companion) $(cfg .facts)
  printf '  %-12s %s (autostart %s) · agent: %s · workdir: %s\n' layout $(cfg .layout) $(cfg .layout_on_start) "$(cfg .agent)" $(cfg .workdir)
  printf '  %-12s %s\n' prompt $(cfg .prompt)
  printf '  %-12s %s %s\n' font "$(cfg .font.family)" $(cfg .font.size)
  printf '  %-12s %s\n' tools "$(cfg '.tools | join(" ")')"
  printf '  %-12s %s\n' terminals "$(terminals_active | tr '\n' ' ')"
}

# ── doctor ────────────────────────────────────────────────────────────
doctor() {
  cfg_init
  local ok=1 t
  chk() { if eval "$2"; then say "$1"; else warn "$1 — $3"; ok=0; fi }
  hooks_ok() {
    local -a c=(${(f)"$(jq -r '[.hooks[]?[]?.hooks[]?.command | select(endswith("companion-event.sh"))] | unique | .[]' $1 2>/dev/null)"})
    (( $#c )) && [[ -x ${c[1]} ]] && (( $#c == 1 ))
  }
  chk "zsh, jq, curl, git"     'has zsh && has jq && has curl && has git' 'run install.sh again'
  chk "frok on PATH"           'has frok' 'add ~/.local/bin to PATH'
  chk "shell hook in rc"       'grep -qsF frok/generated/init.sh ~/.zshrc' 'run frok apply'
  if [[ ${SHELL:t} == zsh && -f ~/.bashrc ]]; then
    local -a gap=(${(f)"$(shell_gap bash zsh)"})
    local -a gp=(${(M)gap:#path *})
    chk "zsh has your bash setup" '(( ! $#gap ))' "zsh lacks $#gp PATH dirs and $(( $#gap - $#gp )) aliases/functions from ~/.bashrc — run \`frok shell port\`"
  fi
  [[ $(cfg .prompt) == starship ]] && chk "starship" 'has starship' 'frok tools install'
  for t in ${(f)"$(cfg '.tools[]?')"}; do chk "tool: $t" "tool_present $t" 'frok tools install'; done
  if [[ $(cfg .companion) != none ]]; then
    for t in $(claude_dirs); do
      # hooked up, and pointing at a script that's actually there (it moves when frok does)
      chk "companion hooks in ${t/#$HOME/~}" "hooks_ok $t/settings.json" 'frok apply'
    done
  fi
  for t in $(terminals_active); do
    case $t in
      windows-terminal) chk "Windows Terminal" "jq -e '.schemes[]? | select(.name | startswith(\"frok \"))' \"$(wt_settings)\" >/dev/null" 'frok apply' ;;
      wezterm) chk "WezTerm" "true" '' ;;
      kitty) chk "kitty" "[[ -f ~/.config/kitty/frok.conf ]]" 'frok apply' ;;
    esac
  done
  (( $(terminals_active | wc -l) )) || warn "no supported terminal found (WezTerm, Windows Terminal, kitty) — themes still apply to the shell and prompt"
  (( ok )) && say "all good"
}

# ── uninstall ─────────────────────────────────────────────────────────
uninstall() {
  local rc
  for rc in ~/.zshrc ~/.bashrc; do [[ -f $rc ]] && sed -i.bak.frok '/frok\/generated\/init.sh/d' $rc; done
  companion_hooks none
  for rc in $(claude_dirs); do [[ -L $rc/skills/frok ]] && rm $rc/skills/frok; done
  local f=$(wt_settings) orig=$FROK_STATE/wt-original.json
  if [[ -n $f && -f $orig ]]; then
    jq --argjson o "$(<$orig)" --arg pet $WT_PET_GUID '
      .schemes = [.schemes[]? | select(.name | startswith("frok ") | not)]
      | .profiles.list = [.profiles.list[] | select(.guid != $pet)
          | . as $p | ($o.profiles | map(select(.guid == $p.guid)) | first) as $was
          | if $was then (del(.colorScheme, .foreground, .font, .backgroundImage, .backgroundImageOpacity, .backgroundImageStretchMode)
                          + ($was | with_entries(select(.value != null)))) else . end]
      | .actions = [.actions[]? | select((.id // "") | startswith("User.frok.") | not)]
      | .keybindings = $o.keybindings
      | .defaultProfile = $o.defaultProfile
      | if $o.startupActions then .startupActions = $o.startupActions else del(.startupActions) end' $f >| $f.frok && mv -f $f.frok $f
    rm -f $orig; say "Windows Terminal restored"
  fi
  local wz=$HOME/.config/wezterm; [[ $OS == wsl ]] && wz="$(win_env USERPROFILE)/.config/wezterm"
  if grep -qs '^-- managed by frok' $wz/wezterm.lua; then
    if [[ -f $wz/wezterm.lua.pre-frok ]]; then mv -f $wz/wezterm.lua.pre-frok $wz/wezterm.lua; else rm -f $wz/wezterm.lua; fi
    say "WezTerm config restored"
  fi
  [[ -f ~/.config/kitty/kitty.conf ]] && sed -i.bak.frok '/^include frok.conf$/d' ~/.config/kitty/kitty.conf && rm -f ~/.config/kitty/frok.conf
  rm -f ~/.local/bin/frok
  say "frok removed (settings kept in $FROK_CONFIG_DIR; installed tools and fonts stay)"
}

# modules.zsh — companion, background, font, tools, Claude skill.

# ── Claude Code config dirs (CLAUDE_CONFIG_DIR, ~/.claude, ccs profiles) ──
claude_dirs() {
  local -aU d
  [[ -n $CLAUDE_CONFIG_DIR ]] && d+=($CLAUDE_CONFIG_DIR)
  [[ -d $HOME/.claude ]] && d+=($HOME/.claude)
  d+=($HOME/.ccs/instances/*(N/))
  print -l $d
}

# How you start Claude Code: plain `claude`, or a ccs account (`ccs personal`),
# most recently used account first.
claude_choices() {
  if has ccs && [[ -f $HOME/.ccs/config.yaml ]]; then
    awk '/^accounts:/{a=1; next} a && /^[^ #]/{a=0} a && /^  [A-Za-z0-9_-]+:/{n=$1; sub(":","",n)} a && /last_used:/{gsub(/"/,"",$2); print $2, n}' \
      $HOME/.ccs/config.yaml | sort -r | awk '{print "ccs " $2}'
  fi
  has claude && print claude
}

# ── companion ─────────────────────────────────────────────────────────
COMPANION_EVENTS='["SessionStart","SessionEnd","UserPromptSubmit","PreToolUse","PostToolUse","PostToolUseFailure","PermissionRequest","Notification","SubagentStart","SubagentStop","PreCompact","Stop"]'

companion_names() { local d; for d in $FROK_HOME/companions/*(N/); do print ${d:t}; done; }

# Hook the companion into every Claude config. Older companion hooks (any
# command ending in companion-event.sh, e.g. the pre-frok install) are replaced.
companion_hooks() {
  local name=$1 dir s cmd="" changed
  [[ $name != none ]] && cmd=$FROK_HOME/companions/$name/companion-event.sh
  for dir in $(claude_dirs); do
    s=$dir/settings.json
    [[ -f $s ]] || { [[ -n $cmd ]] && print '{}' >| $s || continue }
    changed=$(jq --arg cmd "$cmd" --argjson evs $COMPANION_EVENTS '
      def ours: (.command // "") | endswith("companion-event.sh");
      (.hooks // {}) |= (with_entries(.value |= (map(.hooks |= map(select(ours | not))) | map(select((.hooks | length) > 0))))
                         | with_entries(select((.value | length) > 0)))
      | if $cmd == "" then . else
          reduce $evs[] as $e (.; .hooks[$e] = ((.hooks[$e] // []) + [{matcher:"", hooks:[{type:"command", command:$cmd, timeout:5, async:true}]}]))
        end
      | if .hooks == {} then del(.hooks) else . end' $s)
    if [[ $changed != "$(jq . $s)" ]]; then
      cp $s $s.bak.frok
      print -r -- $changed >| $s
      say "companion hooks → ${s/#$HOME/~}"
    fi
  done
}

companion_run() {
  local name=$(cfg .companion); [[ $name == none ]] && name=frog
  export FROK_STATE FROK_GEN FROK_FACTS=$(cfg .facts)
  exec $FROK_HOME/companions/$name/claude-companion.sh
}

# ── background ────────────────────────────────────────────────────────
# Path of the current background (generated on first use), or nothing.
background_file() {
  local b=$(cfg .background)
  case $b in
    none|"") return ;;
    rain)
      local f=$FROK_STATE/backgrounds/rain-${T[slug]}.gif
      [[ -f $f ]] || background_make_rain $f >&2 || return
      print -r -- $f ;;
    *) b=$(expand_home $b); [[ -f $b ]] && print -r -- $b || warn "background file $b not found" ;;
  esac
}

background_make_rain() {
  pkg_install python3 pillow >&2
  step "generating the rain for ${T[name]} (about a minute, once per theme)"
  python3 $FROK_HOME/backgrounds/rain_gen.py $1 ${T[fg]} ${T[accent]} $(mix ${T[accent]} ${T[bg]} 22) >/dev/null \
    || { warn "couldn't generate the rain background"; return 1 }
}

# ── font (Nerd Fonts: icons for eza / starship) ──────────────────────
typeset -gA NERD_ZIP=(
  'CaskaydiaCove Nerd Font' CascadiaCode   'CaskaydiaCove Nerd Font Mono' CascadiaCode
  'JetBrainsMono Nerd Font' JetBrainsMono  'FiraCode Nerd Font' FiraCode
  'Hack Nerd Font' Hack                    'MesloLGS Nerd Font' Meslo
)
typeset -gA NERD_CASK=(
  CascadiaCode font-caskaydia-cove-nerd-font  JetBrainsMono font-jetbrains-mono-nerd-font
  FiraCode font-fira-code-nerd-font           Hack font-hack-nerd-font
  Meslo font-meslo-lg-nerd-font
)

font_install() {
  local family=$(cfg .font.family) zip=${NERD_ZIP[$(cfg .font.family)]}
  [[ -n $zip ]] || return 0                  # not a Nerd Font we know: assume it's installed
  case $OS in
    macos)
      local cask=${NERD_CASK[$zip]}
      brew list --cask $cask >/dev/null 2>&1 || { step "installing $family"; brew install --cask $cask } ;;
    linux)
      fc-list 2>/dev/null | grep -qi "${family% Mono}" && return
      font_fetch $zip $HOME/.local/share/fonts/frok || return
      has fc-cache && fc-cache -f >/dev/null 2>&1; true ;;
    wsl)
      local la=$(win_env LOCALAPPDATA); local dest="$la/Microsoft/Windows/Fonts"
      [[ -n $la ]] || { warn "can't reach Windows from here, so $family isn't installed"; return 1 }
      ls "$dest" /mnt/c/Windows/Fonts 2>/dev/null | grep -qi "${${family// /}%NerdFont*}NerdFont" && return
      local tmp=$(mktemp -d)
      font_fetch $zip $tmp || return
      mkdir -p "$dest"
      cp -f $tmp/*.ttf(N) "$dest/" || { warn "couldn't copy $family into $dest"; rm -rf $tmp; return 1 }
      # register them for this user (no admin needed)
      powershell.exe -NoProfile -Command '
        $d = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
        Get-ChildItem $d -Filter "*NerdFont*.ttf" | ForEach-Object {
          New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts" `
            -Name ($_.BaseName + " (TrueType)") -Value $_.FullName -PropertyType String -Force | Out-Null }' >/dev/null
      rm -rf $tmp
      say "font: $family (Windows; restart Windows Terminal to see it)" ;;
  esac
}

font_fetch() {   # font_fetch <zip name> <dest dir>
  mkdir -p $2
  local z=$(mktemp)
  quietly "downloading the $1 Nerd Font" font_get $z $2 $1; local ok=$?
  rm -f $z
  return $ok
}
font_get() { curl -fsSL -o $1 "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$3.zip" && unzip -oq $1 '*.ttf' -d $2; }

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

# ── Claude skill: the guide that drives `frok` for you ───────────────
skill_install() {
  local dir
  for dir in $(claude_dirs); do
    mkdir -p $dir/skills
    [[ -L $dir/skills/frok || ! -e $dir/skills/frok ]] && ln -sfn $FROK_HOME/guide $dir/skills/frok
  done
}

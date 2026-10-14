# fonts.zsh — Nerd Fonts (icons for eza and starship), downloaded on demand,
# for this user and, from WSL, the Windows side.

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

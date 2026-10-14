# detect.zsh — which terminals are here, and writing frok's look into each.
# Every terminal gets a clearly marked file or block of its own; frok leaves
# the rest of your config alone.

# ── which terminals are here ──────────────────────────────────────────
wezterm_bin() {
  case $OS in
    macos) [[ -x /Applications/WezTerm.app/Contents/MacOS/wezterm ]] && print /Applications/WezTerm.app/Contents/MacOS/wezterm || { has wezterm && print wezterm } ;;
    wsl)   local p; for p in "/mnt/c/Program Files/WezTerm/wezterm.exe" "$(win_env LOCALAPPDATA)/Programs/WezTerm/wezterm.exe"; do [[ -x $p ]] && { print $p; return }; done ;;
    *)     has wezterm && print wezterm ;;
  esac
}
wt_settings() {
  [[ $OS == wsl ]] || return
  local la=$(win_env LOCALAPPDATA) f
  for f in "$la/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json" \
           "$la/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json" \
           "$la/Microsoft/Windows Terminal/settings.json"; do
    [[ -f $f ]] && { print -r -- $f; return }
  done
}
kitty_present() { has kitty || [[ -d /Applications/kitty.app ]]; }

terminals_detected() {
  [[ -n $(wezterm_bin) ]] && print wezterm
  [[ -n $(wt_settings) ]] && print windows-terminal
  kitty_present && print kitty
}
terminals_active() {
  local -a t; t=(${(f)"$(cfg '.terminals[]?')"})
  (( $#t )) && print -l $t || terminals_detected
}

# Files that live on the Windows side when frok runs in WSL.
win_copy() {   # win_copy <file> → Windows path of a copy under %LOCALAPPDATA%\frok
  local la=$(win_env LOCALAPPDATA); [[ -n $la ]] || return 1
  mkdir -p "$la/frok" && cp -f $1 "$la/frok/${1:t}" && wslpath -w "$la/frok/${1:t}"
}

render_terminals() {
  local t
  for t in $(terminals_active); do
    case $t in
      wezterm)          render_wezterm ;;
      windows-terminal) render_wt ;;
      kitty)            render_kitty ;;
    esac
  done
}

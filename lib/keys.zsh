# keys.zsh — one pane keymap for every terminal. macOS uses ⌘, everything
# else Alt (Windows Terminal's own pane keys), so muscle memory carries over.

typeset -gA KEY
if [[ $OS == macos ]]; then
  KEY=(right 'CMD d' down 'CMD|SHIFT d' move 'CMD|ALT' resize 'CMD|SHIFT' close 'CMD|SHIFT w'
       zoom 'CMD z' pet 'CMD|SHIFT k')
  KEYS_HINT='⌘D=split→;⌘⇧D=split↓;⌘⌥←↑↓→=move;⌘⇧W=close pane;⌘⇧K=companion'
else
  KEY=(right 'ALT d' down 'ALT|SHIFT d' move 'ALT' resize 'ALT|SHIFT' close 'CTRL|SHIFT w'
       zoom 'ALT z' pet 'CTRL|SHIFT k')
  KEYS_HINT='Alt+D=split→;Alt+⇧D=split↓;Alt+←↑↓→=move;Ctrl+⇧W=close pane;Ctrl+⇧K=companion'
fi

# The companion's footer shows these.
render_keys() { print -r -- $KEYS_HINT >| $FROK_GEN/keys.txt; }

# 'CMD|SHIFT d' → wezterm mods / key
key_mods() { print -r -- ${KEY[$1]% *}; }
key_key()  { print -r -- ${KEY[$1]##* }; }
# 'ALT|SHIFT d' → Windows Terminal / kitty style 'alt+shift+d'
key_plus() { local k=${KEY[$1]}; k=${k:l}; k=${k//|/+}; print -r -- ${k// /+}; }

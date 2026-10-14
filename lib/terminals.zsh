# terminals.zsh — write the active theme, font, background, keys and layout
# into each terminal's own config. frok owns a clearly marked file or block
# per terminal and leaves the rest of your config alone.

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

# ── WezTerm ───────────────────────────────────────────────────────────
render_wezterm() {
  local dir=$HOME/.config/wezterm zsh_bin=$(command -v zsh) state=$FROK_STATE/companion/companion.state
  local bg=$(background_file) domain=""
  if [[ $OS == wsl ]]; then
    dir="$(win_env USERPROFILE)/.config/wezterm"
    domain="config.default_domain = 'WSL:$WSL_DISTRO_NAME'"
    [[ -n $bg ]] && bg=$(win_copy $bg)
    state=$(wslpath -w $state)
  fi
  mkdir -p $dir
  local f=$dir/wezterm.lua
  if [[ -f $f ]] && ! grep -q '^-- managed by frok' $f; then
    cp $f $f.pre-frok && warn "kept your old WezTerm config as ${f:t}.pre-frok (move personal bits into frok-local.lua)"
  fi
  local op=$(cfg .background_opacity) mac=0; [[ $OS == macos ]] && mac=1
  local -a A B; local i
  for i in 0 1 2 3 4 5 6 7; do A+="'${T[a$i]}'"; B+="'${T[b$i]}'"; done

  {
    print -r -- "-- managed by frok — regenerated on every \`frok\` change. Put your own"
    print -r -- "-- tweaks in frok-local.lua next to this file: return function(config) … end"
    print -r -- "local wezterm = require 'wezterm'
local act = wezterm.action
local mux = wezterm.mux
local config = wezterm.config_builder()
$domain

config.font = wezterm.font_with_fallback { '$(cfg .font.family)', 'CaskaydiaCove Nerd Font', 'Symbols Nerd Font Mono' }
config.font_size = $(cfg .font.size)
config.harfbuzz_features = { 'calt=1', 'liga=1' }
config.freetype_load_target = 'Light'
config.freetype_render_target = 'HorizontalLcd'

-- theme: ${T[name]}
config.colors = {
  foreground = '${T[fg]}', background = '${T[bg]}',
  cursor_bg = '${T[cursor]}', cursor_fg = '${T[bg]}', cursor_border = '${T[cursor]}',
  selection_bg = '${T[selection]}', selection_fg = '${T[fg]}', split = '${T[border]}',
  ansi = { ${(j:, :)A} },
  brights = { ${(j:, :)B} },
  tab_bar = {
    background = '${T[surface]}',
    active_tab = { bg_color = '${T[accent]}', fg_color = '${T[bg]}' },
    inactive_tab = { bg_color = '${T[surface]}', fg_color = '${T[muted]}' },
    inactive_tab_hover = { bg_color = '${T[hover]}', fg_color = '${T[accent]}' },
    new_tab = { bg_color = '${T[surface]}', fg_color = '${T[muted]}' },
    new_tab_hover = { bg_color = '${T[hover]}', fg_color = '${T[accent]}' },
  },
}"
    if [[ -n $bg ]]; then
      print -r -- "
-- background: a seamless tile at a fixed cell size, repeated (more window = more rain)
config.background = {
  { source = { File = { path = [==[$bg]==], speed = 1.0 } }, hsb = { brightness = 0.45 },
    width = '235cell', height = '74cell', repeat_x = 'Repeat', repeat_y = 'Repeat',
    horizontal_align = 'Left', vertical_align = 'Top' },
  { source = { Color = '${T[bg]}' }, width = '100%', height = '100%', opacity = $(printf '%.2f' $(( 1 - op ))) },
}
config.text_background_opacity = 0.0
config.animation_fps = 25 -- the rain GIF is 25fps"
    fi
    print -r -- "
config.inactive_pane_hsb = { saturation = 0.75, brightness = 0.55 }
config.max_fps = 60
config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = false
config.status_update_interval = 1000
config.window_padding = { left = 12, right = 12, top = 10, bottom = 8 }
config.window_decorations = 'TITLE | RESIZE'
config.scrollback_lines = 10000

-- status bar: companion face · folder · git branch · clock
local FACES = { idle = '·ᴥ·', wake = '◕ᴥ◕', thinking = '・ω・', working = '>ᴥ<', ['done'] = '＾ᴥ＾',
  waiting = '•ᴥ•', error = '✖ᴥ✖', dizzy = '@ᴥ@', sleep = '－ᴥ－' }
wezterm.on('update-right-status', function(window, pane)
  local cells = {}
  local sf = io.open([==[$state]==], 'r')
  if sf then
    local line = sf:read '*l'; sf:close()
    local ts, mood = (line or ''):match '(%d+)%s+(%S+)'
    if ts and mood then
      if (mood == 'thinking' or mood == 'working' or mood == 'dizzy' or mood == 'error' or mood == 'wake')
          and (os.time() - tonumber(ts)) > 12 then mood = 'idle' end
      if FACES[mood] then
        table.insert(cells, { Foreground = { Color = '${T[a2]}' } })
        table.insert(cells, { Text = '( ' .. FACES[mood] .. ' )  ' })
      end
    end
  end
  local cwd = pane:get_current_working_dir()
  if cwd then
    local p = (type(cwd) == 'userdata' and cwd.file_path or tostring(cwd)):gsub('/\$', '')
    local name = p:match '([^/\\\\]+)\$'
    if name then
      table.insert(cells, { Foreground = { Color = '${T[accent]}' } })
      table.insert(cells, { Text = '  ' .. name .. '  ' })
    end
  end
  local git = pane:get_user_vars().WEZTERM_GIT
  if git and git ~= '' then
    table.insert(cells, { Foreground = { Color = '${T[accent2]}' } })
    table.insert(cells, { Text = '  ' .. git .. '  ' })
  end
  table.insert(cells, { Foreground = { Color = '${T[muted]}' } })
  table.insert(cells, { Text = wezterm.time.now():format '%H:%M' .. ' ' })
  window:set_right_status(wezterm.format(cells))
end)

-- keys (the same pane keys frok sets in every terminal)
config.keys = {
  { key = '$(key_key right)', mods = '$(key_mods right)', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = '$(key_key down)', mods = '$(key_mods down)', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = 'LeftArrow', mods = '$(key_mods move)', action = act.ActivatePaneDirection 'Left' },
  { key = 'RightArrow', mods = '$(key_mods move)', action = act.ActivatePaneDirection 'Right' },
  { key = 'UpArrow', mods = '$(key_mods move)', action = act.ActivatePaneDirection 'Up' },
  { key = 'DownArrow', mods = '$(key_mods move)', action = act.ActivatePaneDirection 'Down' },
  { key = 'LeftArrow', mods = '$(key_mods resize)', action = act.AdjustPaneSize { 'Left', 3 } },
  { key = 'RightArrow', mods = '$(key_mods resize)', action = act.AdjustPaneSize { 'Right', 3 } },
  { key = 'UpArrow', mods = '$(key_mods resize)', action = act.AdjustPaneSize { 'Up', 3 } },
  { key = 'DownArrow', mods = '$(key_mods resize)', action = act.AdjustPaneSize { 'Down', 3 } },
  { key = '$(key_key close)', mods = '$(key_mods close)', action = act.CloseCurrentPane { confirm = true } },
  { key = '$(key_key zoom)', mods = '$(key_mods zoom)', action = act.TogglePaneZoomState },"
    (( mac )) && print -r -- "  { key = 'c', mods = 'CMD', action = act.CopyTo 'ClipboardAndPrimarySelection' },
  { key = 'v', mods = 'CMD', action = act.PasteFrom 'Clipboard' },
  { key = 't', mods = 'CMD', action = act.SpawnTab 'CurrentPaneDomain' },
  { key = 'k', mods = 'CMD', action = act.ClearScrollback 'ScrollbackOnly' },"
    print -r -- "}"
    [[ $(cfg .layout_on_start) == true ]] && wezterm_layout_lua $zsh_bin
    print -r -- "
local ok, mine = pcall(require, 'frok-local')
if ok and type(mine) == 'function' then mine(config) end
return config"
  } >| $f
  say "WezTerm → $f"
}

# gui-startup: open maximized and build the layout once the window settles.
wezterm_layout_lua() {
  local zsh_bin=$1 i id cmd args parent d
  local dir=$(expand_home $(cfg .workdir))
  load_layout $(cfg .layout)
  print -r -- "
-- layout: $(cfg .layout)
wezterm.on('gui-startup', function()
  local function run(cmd, dir) return { '$zsh_bin', '-ic', 'cd \"' .. dir .. '\" && ' .. cmd .. '; exec $zsh_bin -i' } end"
  for (( i = 1; i <= $#L_id; i++ )); do
    cmd=$(pane_cmd ${L_run[i]}); d=$(expand_home ${L_cwd[i]})
    [[ -n $cmd ]] && args="args = run([==[$cmd]==], [==[$d]==]), " || args=""
    if (( i == 1 )); then
      print -r -- "  local tab, p_${L_id[i]}, window = mux.spawn_window { cwd = [==[$d]==], ${args}}
  local gw = window:gui_window(); gw:maximize()
  local function build()"
    else
      local dd=Right; [[ ${L_dir[i]} == down ]] && dd=Bottom
      print -r -- "    local p_${L_id[i]} = p_${L_split[i]}:split { direction = '$dd', size = ${L_size[i]}, cwd = [==[$d]==], ${args}}"
    fi
  done
  print -r -- "    p_${L_focus}:activate()
  end
  local last = -1
  local function settle(n)
    local ok, d = pcall(function() return gw:get_dimensions() end)
    local h = (ok and d) and d.pixel_height or 0
    if (h > 0 and h == last) or n <= 0 then build() else last = h; wezterm.time.call_after(0.2, function() settle(n - 1) end) end
  end
  wezterm.time.call_after(0.3, function() settle(15) end)
end)"
}

# ── Windows Terminal (from WSL) ───────────────────────────────────────
WT_PET_GUID='{9b6c1f3e-7a2d-4f0e-b5c8-3e1d6a9f0c42}'

# wt.exe command line for the active layout (also used by `frok layout open`)
wt_layout_cmdline() {
  local guid=$1 i cmd parts=() line
  load_layout $(cfg .layout)
  # FROK_PANE = the pane's id in the tab (creation order), so the companion can
  # focus it with `wt.exe focus-pane`
  pane_line() {   # pane_line <run> <dir> <pane id>
    local c=$(pane_cmd $1) dir=$2
    if [[ -n $c ]]; then print -r -- "-p \"$guid\" wsl.exe -d $WSL_DISTRO_NAME --cd \"$dir\" -- env FROK_PANE=$3 zsh -ic \"${c//\"/\\\"}\\; exec zsh -i\""
    else print -r -- "-p \"$guid\" wsl.exe -d $WSL_DISTRO_NAME --cd \"$dir\" -- env FROK_PANE=$3 zsh -il"; fi
  }
  parts+=("new-tab --title frok $(pane_line ${L_run[1]} ${L_cwd[1]} 0)")
  for (( i = 2; i <= $#L_id; i++ )); do
    local o=-V; [[ ${L_dir[i]} == down ]] && o=-H
    parts+=("focus-pane -t $(( $(pane_index ${L_split[i]}) - 1 ))")
    parts+=("split-pane $o -s ${L_size[i]} $(pane_line ${L_run[i]} ${L_cwd[i]} $(( i - 1 )))")
  done
  parts+=("focus-pane -t $(( $(pane_index $L_focus) - 1 ))")
  print -r -- ${(j: ; :)parts}
}

render_wt() {
  local f=$(wt_settings); [[ -n $f ]] || return
  local bk=$FROK_STATE/backups; mkdir -p $bk
  cp $f "$bk/wt-settings-$(date +%Y%m%d-%H%M%S).json"
  ls -t $bk/wt-settings-*.json | tail -n +6 | xargs -r rm -f

  # the WSL profiles for this distro (WT can list the same distro twice)
  local guids=$(jq -c --arg d $WSL_DISTRO_NAME '[.profiles.list[] | select((.name == $d) and ((.source // "") | test("WSL|Wsl|CanonicalGroup")) and (.hidden != true)) | .guid]' $f)
  [[ $guids == '[]' ]] && { warn "Windows Terminal has no visible '$WSL_DISTRO_NAME' profile; skipped"; return }
  local main=$(jq -r '.[0]' <<< $guids)

  # remember what we change the first time, so `frok uninstall` can put it back
  local orig=$FROK_STATE/wt-original.json
  [[ -f $orig ]] || jq --argjson g "$guids" '{
      defaultProfile, startupActions,
      profiles: [.profiles.list[] | select(.guid | IN($g[])) | {guid, colorScheme, foreground, font, backgroundImage, backgroundImageOpacity, backgroundImageStretchMode}],
      keybindings: [.keybindings[]? | select((.id // "") | startswith("User.frok.") | not)] }' $f >| $orig

  local bg=$(background_file) bgw=""
  [[ -n $bg ]] && bgw=$(win_copy $bg)
  local scheme=$(jq -n --arg n "frok ${T[name]}" --argjson t "$(jq -n \
      --arg bg ${T[bg]} --arg fg ${T[fg]} --arg cu ${T[cursor]} --arg se ${T[selection]} \
      '{background:$bg, foreground:$fg, cursorColor:$cu, selectionBackground:$se}')" '$t + {name:$n}')
  local i names=(black red green yellow blue purple cyan white)
  for i in 0 1 2 3 4 5 6 7; do
    scheme=$(jq --arg k ${names[i+1]} --arg v ${T[a$i]} --arg bk bright${(C)names[i+1]} --arg bv ${T[b$i]} '.[$k]=$v | .[$bk]=$bv' <<< $scheme)
  done
  local look=$(jq -n --arg s "frok ${T[name]}" --arg fg ${T[fg]} --arg face "$(cfg .font.family)" \
      --argjson size $(cfg .font.size) --arg bg "$bgw" --argjson op $(cfg .background_opacity) '
    {colorScheme:$s, foreground:$fg, font:{face:$face, size:$size},
     backgroundImage:$bg, backgroundImageOpacity:(if $bg == "" then 0 else $op end),
     backgroundImageStretchMode:"uniformToFill"}')
  local layout=$(wt_layout_cmdline $main)
  local actions=$(jq -n --arg layout "$layout" '[
    {id:"User.frok.right", command:{action:"splitPane", split:"right", splitMode:"duplicate"}},
    {id:"User.frok.down", command:{action:"splitPane", split:"down", splitMode:"duplicate"}},
    {id:"User.frok.zoom", command:"togglePaneZoom"},
    {id:"User.frok.layout", command:{action:"wt", commandline:$layout}}]')
  local kb=$(jq -n --arg r $(key_plus right) --arg d $(key_plus down) --arg z $(key_plus zoom) '[
    {id:"User.frok.right", keys:$r}, {id:"User.frok.down", keys:$d}, {id:"User.frok.zoom", keys:$z},
    {id:"User.frok.layout", keys:"ctrl+shift+l"}]')
  local startup=""; [[ $(cfg .layout_on_start) == true ]] && startup=$layout

  jq --argjson scheme "$scheme" --argjson g "$guids" --argjson look "$look" --arg pet $WT_PET_GUID \
     --argjson actions "$actions" --argjson kb "$kb" --arg main $main --arg startup "$startup" \
     --argjson origstart "$(jq '.startupActions' $orig)" '
    ($kb | map(.keys)) as $ours
    | .schemes = ([.schemes[]? | select(.name | startswith("frok ") | not)] + [$scheme])
    | .profiles.list = [.profiles.list[] | select(.guid != $pet)       # drop the old companion profile
        | if (.guid | IN($g[])) then . + $look else . end]
    | .actions = ([.actions[]? | select((.id // "") | startswith("User.frok.") | not)] + $actions)
    | .keybindings = ([.keybindings[]? | select((.id // "") | startswith("User.frok.") | not)
        | select(.keys | IN($ours[]) | not)] + $kb)
    | .defaultProfile = $main
    | if $startup != "" then .startupActions = $startup
      elif $origstart != null then .startupActions = $origstart else del(.startupActions) end
  ' $f >| $f.frok && mv -f $f.frok $f
  say "Windows Terminal → ${f:t} (profile '$WSL_DISTRO_NAME' is now the default)"
}

# ── kitty ─────────────────────────────────────────────────────────────
render_kitty() {
  local dir=$HOME/.config/kitty; mkdir -p $dir
  local m=${${KEY[right]%% *}:l}; m=${m//|/+}     # cmd / alt
  local mv=${${KEY[move]:l}//|/+} rs=${${KEY[resize]:l}//|/+}
  {
    print "# generated by frok — don't edit, run \`frok\` instead"
    print "font_family $(cfg .font.family)\nfont_size $(cfg .font.size)"
    print "foreground ${T[fg]}\nbackground ${T[bg]}\ncursor ${T[cursor]}\nselection_background ${T[selection]}"
    local i; for i in 0 1 2 3 4 5 6 7; do print "color$i ${T[a$i]}\ncolor$((i + 8)) ${T[b$i]}"; done
    print "active_border_color ${T[accent]}\ninactive_border_color ${T[border]}\ninactive_text_alpha 0.6"
    print "tab_bar_background ${T[surface]}\nactive_tab_background ${T[accent]}\nactive_tab_foreground ${T[bg]}"
    print "inactive_tab_background ${T[surface]}\ninactive_tab_foreground ${T[muted]}"
    print "allow_remote_control socket-only\nlisten_on unix:/tmp/kitty-{kitty_pid}\nenabled_layouts splits,stack"
    print "map $(key_plus right) launch --location=vsplit --cwd=current"
    print "map $(key_plus down) launch --location=hsplit --cwd=current"
    local d; for d in left right up down; do print "map $mv+$d neighboring_window $d"; done
    print "map $rs+left resize_window narrower 3\nmap $rs+right resize_window wider 3"
    print "map $rs+up resize_window taller 3\nmap $rs+down resize_window shorter 3"
    print "map $(key_plus close) close_window\nmap $(key_plus zoom) toggle_layout stack"
  } >| $dir/frok.conf
  grep -qsx 'include frok.conf' $dir/kitty.conf || print '\ninclude frok.conf' >> $dir/kitty.conf
  say "kitty → $dir/frok.conf"
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

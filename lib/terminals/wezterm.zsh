# wezterm.zsh — WezTerm: theme, font, background, keys, status bar and layout,
# all in a generated wezterm.lua (yours kept as wezterm.lua.pre-frok).

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
config.text_background_opacity = 1.0
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

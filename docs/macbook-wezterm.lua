-- ~/.config/wezterm/wezterm.lua
-- Matrix terminal: animated digital-rain background + classic phosphor green.
local wezterm = require 'wezterm'
local act = wezterm.action
local config = wezterm.config_builder()

-- ── Font ──────────────────────────────────────────────────────────────
-- Cascadia Code (Nerd Font) — same family as Windows Terminal, with icon glyphs.
-- PingFang carries the katakana fallback if any ever shows up in the shell.
config.font = wezterm.font_with_fallback {
  'Menlo',                     -- picked in Pond Palettes
  'CaskaydiaCove Nerd Font',   -- nerd glyphs / icons fallback
  'PingFang HK',
}
config.font_size = 14.0
config.line_height = 1.0
config.harfbuzz_features = { 'calt=1', 'liga=1' } -- coding ligatures
-- Smoother, macOS/iTerm-like glyphs: don't let FreeType snap strokes to pixels.
config.freetype_load_target = 'Light'          -- light vertical-only hinting: smooth shapes, crisp baselines
config.freetype_render_target = 'HorizontalLcd' -- subpixel AA (ClearType-style), sharper on non-Retina screens

-- ── Classic Matrix green color scheme ─────────────────────────────────
config.colors = {
  -- Tokyo Night
  foreground = '#c0caf5',
  background = '#1a1b26',
  cursor_bg = '#c0caf5',
  cursor_fg = '#1a1b26',
  cursor_border = '#c0caf5',
  selection_bg = '#33467c',
  selection_fg = '#c0caf5',
  split = '#3b4261',
  ansi    = { '#15161e', '#f7768e', '#9ece6a', '#e0af68', '#7aa2f7', '#bb9af7', '#7dcfff', '#a9b1d6' },
  brights = { '#414868', '#f7768e', '#9ece6a', '#e0af68', '#7aa2f7', '#bb9af7', '#7dcfff', '#c0caf5' },
  tab_bar = {
    background = '#16161e',
    active_tab = { bg_color = '#7aa2f7', fg_color = '#1a1b26' },
    inactive_tab = { bg_color = '#16161e', fg_color = '#545c7e' },
    inactive_tab_hover = { bg_color = '#292e42', fg_color = '#7aa2f7' },
    new_tab = { bg_color = '#16161e', fg_color = '#545c7e' },
    new_tab_hover = { bg_color = '#292e42', fg_color = '#7aa2f7' },
  },
}

-- ── Animated Matrix rain background ───────────────────────────────────
config.background = {
  {
    source = { File = { path = wezterm.home_dir .. '/.config/wezterm/rain-tokyo-tile-25.gif', speed = 1.0 } },
    hsb = { brightness = 0.45, hue = 1.0, saturation = 1.0 },
    -- A seamless tile at a fixed size (the look it has on a Full HD screen),
    -- repeated to fill the window: a bigger window shows more rain instead of
    -- stretched rain. Sized in cells so it also stays the same across DPIs.
    width = '235cell',
    height = '74cell',   -- 660px tile x 1.9 / 17px rows
    repeat_x = 'Repeat',
    repeat_y = 'Repeat',
    horizontal_align = 'Left',
    vertical_align = 'Top',
  },
  {
    source = { Color = '#1a1b26' },
    width = '100%',
    height = '100%',
    opacity = 0.80,
  },
}
config.text_background_opacity = 0.0
-- WezTerm has no per-pane border colour, so mark the active split by dimming
-- the others instead (Kitty's bright active border was the inspiration).
config.inactive_pane_hsb = { saturation = 0.75, brightness = 0.55 }
config.window_background_opacity = 1.0
config.animation_fps = 25 -- must match the rain GIF's 25fps (40ms frames), or frames get dropped
config.max_fps = 60

-- ── Tab bar / status bar ──────────────────────────────────────────────
config.use_fancy_tab_bar = false
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = false -- always show the top bar (status: face, cwd, branch, clock)
config.tab_bar_at_bottom = false
config.window_frame = { font = wezterm.font 'Menlo', font_size = 12.0 }
config.status_update_interval = 1000 -- refresh status bar (companion face) ~1s

local function basename(s)
  return (s:gsub('(.*[/\\])(.*)', '%2'))
end

-- Right status: current folder + git branch (fed from the zsh hook) + clock.
local COMPANION_FACES = {
  idle = '·ᴥ·', wake = '◕ᴥ◕', thinking = '・ω・', working = '>ᴥ<',
  ['done'] = '＾ᴥ＾', waiting = '•ᴥ•', error = '✖ᴥ✖', dizzy = '@ᴥ@', sleep = '－ᴥ－',
}

wezterm.on('update-right-status', function(window, pane)
  local cells = {}

  -- companion mood face, read from the state file the hooks write
  local sf = io.open(wezterm.home_dir .. '/.config/terminal/companion.state', 'r')
  if sf then
    local line = sf:read '*l'; sf:close()
    local ts, mood = (line or ''):match '(%d+)%s+(%S+)'
    if ts and mood then
      if (mood == 'thinking' or mood == 'working' or mood == 'dizzy'
          or mood == 'error' or mood == 'wake') and (os.time() - tonumber(ts)) > 12 then
        mood = 'idle'
      end
      local face = COMPANION_FACES[mood]
      if face then
        table.insert(cells, { Foreground = { Color = '#9ece6a' } })
        table.insert(cells, { Text = '( ' .. face .. ' )  ' })
      end
    end
  end

  local cwd_uri = pane:get_current_working_dir()
  if cwd_uri then
    local p = type(cwd_uri) == 'userdata' and cwd_uri.file_path or tostring(cwd_uri)
    p = p:gsub('^file://[^/]*', ''):gsub('/$', '')
    local name = basename(p)
    if name ~= '' then
      table.insert(cells, { Foreground = { Color = '#7aa2f7' } })
      table.insert(cells, { Text = '  ' .. name .. '  ' })
    end
  end

  local vars = pane:get_user_vars()
  if vars.WEZTERM_GIT and vars.WEZTERM_GIT ~= '' then
    table.insert(cells, { Foreground = { Color = '#bb9af7' } })
    table.insert(cells, { Text = '  ' .. vars.WEZTERM_GIT .. '  ' })
  end

  table.insert(cells, { Foreground = { Color = '#565f89' } })
  table.insert(cells, { Text = '󰥔 ' .. wezterm.time.now():format '%H:%M' .. ' ' })

  window:set_right_status(wezterm.format(cells))
end)

-- ── Window chrome ─────────────────────────────────────────────────────
config.window_padding = { left = 12, right = 12, top = 10, bottom = 8 }
config.window_decorations = 'TITLE | RESIZE' -- keep the title bar (draggable between screens)
config.initial_cols = 200 -- large fallback size so splits are proportional even if maximize is slow
config.initial_rows = 50
config.scrollback_lines = 10000

-- ── Keys: copy/paste + splits + pane navigation ───────────────────────
config.keys = {
  -- copy / paste
  { key = 'c', mods = 'CMD', action = act.CopyTo 'ClipboardAndPrimarySelection' },
  { key = 'v', mods = 'CMD', action = act.PasteFrom 'Clipboard' },

  -- open a new split (inherits the current pane's cwd)
  { key = 'd', mods = 'CMD',        action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } }, -- → to the right
  { key = 'd', mods = 'CMD|SHIFT',  action = act.SplitVertical   { domain = 'CurrentPaneDomain' } }, -- ↓ below

  -- move between splits
  { key = 'LeftArrow',  mods = 'CMD|ALT', action = act.ActivatePaneDirection 'Left' },
  { key = 'RightArrow', mods = 'CMD|ALT', action = act.ActivatePaneDirection 'Right' },
  { key = 'UpArrow',    mods = 'CMD|ALT', action = act.ActivatePaneDirection 'Up' },
  { key = 'DownArrow',  mods = 'CMD|ALT', action = act.ActivatePaneDirection 'Down' },

  -- resize the active split
  { key = 'LeftArrow',  mods = 'CMD|SHIFT', action = act.AdjustPaneSize { 'Left', 3 } },
  { key = 'RightArrow', mods = 'CMD|SHIFT', action = act.AdjustPaneSize { 'Right', 3 } },
  { key = 'UpArrow',    mods = 'CMD|SHIFT', action = act.AdjustPaneSize { 'Up', 3 } },
  { key = 'DownArrow',  mods = 'CMD|SHIFT', action = act.AdjustPaneSize { 'Down', 3 } },

  -- close the active split
  { key = 'w', mods = 'CMD|SHIFT', action = act.CloseCurrentPane { confirm = true } },

  -- maximize (zoom) the active split, new tab, clear scrollback
  { key = 'z', mods = 'CMD', action = act.TogglePaneZoomState },
  { key = 't', mods = 'CMD', action = act.SpawnTab 'CurrentPaneDomain' },
  { key = 'k', mods = 'CMD', action = act.ClearScrollback 'ScrollbackOnly' },
}

-- ── Startup: open maximized with a 2×2 grid of panes, all in ~/dev ─────
local mux = wezterm.mux
wezterm.on('gui-startup', function()
  local dev = wezterm.home_dir .. '/dev'
  -- Size the window to the active screen up front so the 50/50 splits are
  -- even (maximize() is async and would skew the first split).
  local personal = dev .. '/personal'
  -- Launch a program in a pane via its own interactive shell, then drop back
  -- to a shell when it exits. Running it as the pane's `args` (not by typing
  -- into a live shell) avoids the autocorrect/half-ready-shell garble.
  local function prog(cmd) return { '/bin/zsh', '-ic', cmd .. '; exec /bin/zsh -i' } end
  -- cd explicitly, since the pane `cwd` option isn't reliably honored for launched args
  local function prog_cd(dir, cmd) return { '/bin/zsh', '-ic', 'cd "' .. dir .. '" && ' .. cmd .. '; exec /bin/zsh -i' } end

  local tab, pane, window = mux.spawn_window { cwd = dev, args = prog 'companion' }
  local gw = window:gui_window()
  gw:maximize()

  local function do_splits()
    local right   = pane:split  { direction = 'Right',  size = 0.5,   cwd = personal, args = prog_cd(personal, 'ccs personal') }
    local lower   = pane:split  { direction = 'Bottom', size = 7 / 8, cwd = dev }                               -- plain ~/dev shell
    local leftBot = lower:split { direction = 'Bottom', size = 5 / 7, cwd = personal, args = prog_cd(personal, 'ccs personal') }
    right:split  { direction = 'Bottom', size = 0.5, cwd = personal, args = prog_cd(personal, 'ccs personal') }
    pane:activate()
  end

  -- Split only once the window has stopped resizing (maximize is async). Poll the
  -- height until two readings match, so the fractions land on the final size.
  local last_h = -1
  local function wait_split(n)
    local ok, dims = pcall(function() return gw:get_dimensions() end)
    local h = (ok and dims) and dims.pixel_height or 0
    if (h > 0 and h == last_h) or n <= 0 then
      do_splits()
    else
      last_h = h
      wezterm.time.call_after(0.2, function() wait_split(n - 1) end)
    end
  end
  wezterm.time.call_after(0.3, function() wait_split(15) end)
end)

return config

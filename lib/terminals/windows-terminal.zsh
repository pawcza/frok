# windows-terminal.zsh — Windows Terminal, configured from WSL: a colour
# scheme, the WSL profile's look, User.frok.* actions and keys, the layout.

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

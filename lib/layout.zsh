# layout.zsh — pane layouts. A layout is a list of panes; each pane after the
# first splits an earlier one (dir right|down, size = the new pane's share).
# Terminals turn the same list into their own startup code.

layout_file() {
  local d; for d in $FROK_CONFIG_DIR/layouts $FROK_HOME/layouts; do
    [[ -f $d/$1.json ]] && { print $d/$1.json; return }
  done
}
layout_names() { local d f; for d in $FROK_HOME/layouts $FROK_CONFIG_DIR/layouts; do for f in $d/*.json(N); do print ${f:t:r}; done; done | sort -u; }

# load_layout <name> → arrays L_id L_split L_dir L_size L_run (index-aligned), L_focus
load_layout() {
  local f=$(layout_file $1); [[ -n $f ]] || die "no layout called '$1' (try: frok layout)"
  L_id=() L_split=() L_dir=() L_size=() L_run=()
  local id sp dr sz rn
  while IFS=$'\t' read -r id sp dr sz rn; do
    L_id+=($id) L_split+=($sp) L_dir+=($dr) L_size+=($sz) L_run+=($rn)
  done < <(jq -r '.panes[] | [.id, (.split // "-"), (.dir // "-"), (.size // 0 | tostring), (.run // "shell")] | @tsv' $f)
  L_focus=$(jq -r '.focus // .panes[0].id' $f)
}

# index (1-based) of a pane id
pane_index() { print ${L_id[(ie)$1]}; }

# What a pane runs, as a shell command line ("" = just a shell).
pane_cmd() {
  case $1 in
    companion) [[ $(cfg .companion) == none ]] && print "" || print "$HOME/.local/bin/frok companion run" ;;
    agent)     cfg .agent ;;
    shell)     print "" ;;
    *)         print -r -- $1 ;;
  esac
}

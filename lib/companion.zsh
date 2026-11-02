# companion.zsh: the companion pane: pets, and starting it.

# The companion is one engine (companion/) with a choice of pets.
COMPANION_DIR=$FROK_HOME/companion
companion_names() { local f; for f in $COMPANION_DIR/pets/*.zsh(N); do print ${f:t:r}; done; }
# pet_art <name> — the pet's resting face, for previews
pet_art() {
  ( source $COMPANION_DIR/pets/$1.zsh 2>/dev/null || exit
    local l; for l in "${PET_ART[@]}"; do print -r -- ${${${l//\{1\}/$PET_EYE}//\{2\}/$PET_EYE}//\{m\}/${PET_MOUTH[rest]}}; done )
}

companion_run() {
  local name=$(cfg .companion); [[ $name == (none|frog) ]] && name=frok
  export FROK_STATE FROK_GEN FROK_CFG FROK_FACTS=$(cfg .facts) FROK_PET=$name
  export FROK_AGENT_WATCH="$(cfg '.agents_watch[]?' | tr '\n' ' ')"
  load_theme $(cfg .theme)                 # chip colours for the companion's footer
  export FROK_UI="${T[hover]} ${T[border]} ${T[accent]} ${T[fg]} ${T[muted]}"
  exec $COMPANION_DIR/companion.zsh
}

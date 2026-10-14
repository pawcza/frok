# pet.zsh — the pet: load its file (pets/<name>.zsh) and draw it, with its
# face following the most urgent session.

# ── the pet: art, faces and tricks (pets/<name>.zsh, see pets/README.md) ──
PET=${FROK_PET:-frok}; [[ -r $HERE/pets/$PET.zsh ]] || PET=frok
PET_ALT=(); PET_IDLE=(); unfunction pet_trick pet_start pet_frame 2>/dev/null
source $HERE/pets/$PET.zsh
typeset -A trickkey trickframes
for t in $PET_TRICKS; do trickkey[${t%%:*}]=${${t#*:}%%:*}; trickframes[${${t#*:}%%:*}]=${t##*:}; done

# ── pet animation ─────────────────────────────────────────────────────
# The pet's face follows the most urgent session; state changes trigger short
# reactions (error → x_x + shiver, done → yay, needs you → alert) and, when
# nothing's happening, it does random tricks. Everything stays in fixed cells.
typeset -A oldst
ev=""; ev_until=0; quiet=0
annoy=0; last_click=0; phase=""; phase_t=0   # clicks on the pet annoy it
start_ev() { ev=$1; ev_until=$(( tick + $2 )); (( $+functions[pet_start] )) && pet_start $1; }
start_trick() { start_ev $1 ${trickframes[$1]:-12}; }
spin=('|' '/' '-' '\'); qs=('?' '..' '...'); dz=('@' 'o' 'O' 'o')

build_frog() {
  local o=$PET_EYE e1=$PET_EYE e2=$PET_EYE mouth=${PET_MOUTH[rest]} bub="" bc=$Y shx=0 off=0 fc=$ec left
  local alt=0 dy=0 hide=0
  local -a marg mc; marg=("" "" ""); mc=($Y $W $W)
  (( tick >= ev_until )) && ev=""
  if [[ -z $ev && -z $phase && ( $top == idle || $top == done || $top == bg ) ]] && (( annoy == 0 && quiet <= 600 && $#PET_IDLE && RANDOM % 110 == 0 )); then
    start_trick ${PET_IDLE[RANDOM % $#PET_IDLE + 1]}
  fi
  (( $+functions[pet_frame] )) && pet_frame
  # base expression from the most urgent session
  case $top in
    working)  e1='>'; e2='<'; (( (tick/2) % 2 )) && mouth=${PET_MOUTH[talk]}; bub=${spin[tick % 4 + 1]} ;;
    thinking) (( (tick/6) % 2 )) && { e1='.'; e2='.'; }; bub=${qs[(tick/3) % 3 + 1]} ;;
    waiting)  e1='O'; e2='O'; mouth=${PET_MOUTH[open]}; (( (tick/3) % 2 )) && bub='!' ;;
    error)    e1='x'; e2='x'; mouth=${PET_MOUTH[sad]}; bub='x_x'; bc=$R ;;
    dizzy)    e1=${dz[tick % 4 + 1]}; e2=${dz[(tick + 2) % 4 + 1]}; bub='~' ;;
    done)     e1='^'; e2='^'; mouth=${PET_MOUTH[happy]} ;;
    bg)       bub=${qs[(tick/4) % 3 + 1]} ;;
  esac
  # dozing off after 10 quiet minutes
  if [[ $top == idle ]] && (( quiet > 600 )) && [[ -z $ev ]]; then
    e1='-'; e2='-'; bub=""
    local zr=$(( 3 - (tick / 5) % 3 )); marg[$zr]="${(l:$((7 - zr)):)}${${:-z Z z}[$(( (tick / 5) % 3 * 2 + 1 ))]}"; mc[$zr]=$D
  fi
  # short reactions and tricks override the base face: the pet's own first
  left=$(( ev_until - tick ))
  if [[ -n $ev ]] && ! { (( $+functions[pet_trick] )) && pet_trick $ev; }; then
    case $ev in
      dead)   e1='x'; e2='x'; mouth=${PET_MOUTH[sad]}; bub='x_x'; bc=$R; (( left > 18 && tick % 2 )) && shx=1 ;;
      yay)    e1='^'; e2='^'; mouth=${PET_MOUTH[happy]}; (( (tick/2) % 2 )) && bub='yay!' || bub='\o/'
              marg[2]="${(l:$(( RANDOM % 6 + 1 )):)}*"; mc[2]=$Y; marg[3]="${(l:$(( RANDOM % 7 + 1 )):)}+"; mc[3]=$Y ;;
      alert)  e1='O'; e2='O'; mouth=${PET_MOUTH[open]}; bub='!!' ;;
      wink)   e1='-' ;;
      googly) e1='O'; e2='.' ;;
      look)   (( left > 4 )) && { e1='.'; e2=$o; } || { e1=$o; e2='.'; } ;;
      roll)   local rl=("$o" '.' ',' '.'); e1=${rl[left % 4 + 1]}; e2=$e1 ;;
      tongue) mouth=${PET_MOUTH[tongue]}; bub=':P' ;;
      dizzy)  e1=${dz[tick % 4 + 1]}; e2=${dz[(tick + 2) % 4 + 1]}; bub='~@~' ;;
      nap)    e1='-'; e2='-'; bub=""
              local nr=$(( 3 - (tick / 4) % 3 )); marg[$nr]="${(l:$((7 - nr)):)}${${:-z Z z}[$(( (tick / 4) % 3 * 2 + 1 ))]}"; mc[$nr]=$D ;;
    esac
  fi
  # ── annoyance (clicks on the pet), overrides everything ──────────────
  (( annoy > 0 && tick - last_click > 15 && tick % 15 == 0 )) && (( annoy-- ))
  if [[ -z $phase ]] && (( annoy > 0 )); then
    if   (( annoy <= 2 )); then e1=$o; e2='-'; bub='hey!'
    elif (( annoy <= 4 )); then e1='='; e2='='; mouth=${PET_MOUTH[rest]}; bub='stop it'
    elif (( annoy <= 6 )); then e1='\'; e2='/'; mouth=${PET_MOUTH[grit]}; bub='grr'; bc=$R; fc=$R; (( tick % 2 )) && shx=1
    elif (( annoy <= 9 )); then e1='\'; e2='/'; mouth=${PET_MOUTH[angry]}; (( (tick/2) % 2 )) && bub='GRRR' || bub='!!!'
                               bc=$R; (( tick % 2 )) && fc=$R || fc=$Y; shx=$(( RANDOM % 3 ))
    else                        e1='@'; e2='@'; mouth=${PET_MOUTH[angry]}; bub='ENOUGH'; bc=$R; fc=$R; shx=$(( RANDOM % 4 )); fi
  fi
  if [[ -n $phase ]]; then
    local pt=$(( tick - phase_t ))
    case $phase in
      bye)   e1='-'; e2='-'; mouth=${PET_MOUTH[rest]}; bub='bye.'; bc=$D; fc=$ec
             (( pt >= 10 )) && { phase=leave; phase_t=$tick; } ;;
      leave) off=$(( pt * 2 )); (( off >= 31 )) && { off=31; phase=gone; phase_t=$tick; } ;;
      gone)  off=31; (( pt >= 125 )) && { phase=back; phase_t=$tick; } ;;
      back)  off=$(( 31 - pt * 2 )); (( off <= 0 )) && { off=0; phase=hmph; phase_t=$tick; } ;;
      hmph)  e1='-'; e2=$o; bub='hmph.'; bc=$D; (( pt >= 25 )) && { phase=""; annoy=0; } ;;
    esac
  fi

  # occasional blink when calm
  [[ -z $ev && -z $phase && annoy -eq 0 && ( $top == idle || $top == bg ) && $e1 == $o ]] && (( blink )) && { e1='-'; e2='-'; }
  [[ -n $bub ]] && { marg[1]="${(l:8:)bub}"; mc[1]=$bc; }

  # the art with this frame's eyes and mouth, maybe its second frame, bobbing by dy
  local -a src art; local i l
  (( alt && $#PET_ALT )) && src=("${PET_ALT[@]}") || src=("${PET_ART[@]}")
  for (( i = 1; i <= 6; i++ )); do
    l=${src[i - dy]}; (( i - dy < 1 )) && l=""
    (( hide )) && l=""
    art[i]=${${${l//\{1\}/$e1}//\{2\}/$e2}//\{m\}/$mouth}
  done
  local sp="${(l:shx:)}"
  frogrow=()
  if (( off > 0 )); then                         # sliding away / back in, or gone
    for i in {1..6}; do frogrow[$i]="${fc}${(r:31:)${art[$i][off+1,-1]}}${X}"; done
    if [[ $phase == gone ]]; then
      frogrow[3]="${D}${(r:31:):-       $PET_GONE}${X}"
      frogrow[6]="${D}${(r:31:):-  .   .   .   .}${X}"
    fi
    return
  fi
  # rows 1-3: bubbles and props in the first 9 columns, then the art
  for i in 1 2 3; do frogrow[$i]="${mc[$i]}${(r:9:)marg[$i]}${X}${fc}${(r:22:)${:-$sp${art[$i][10,-1]}}}${X}"; done
  for i in 4 5 6; do frogrow[$i]="${fc}${(r:31:)${:-$sp${art[$i]}}}${X}"; done
}

# ghost — floats, says boo, fades away.
PET_LABEL=ghost
PET_GONE="(it left)"
PET_EYE='o'
PET_ART=(
'             .-----.'
'            / {1}   {2} \'
'           |    {m}    |'
'           |         |'
'           |/\/\/\/\/|'
''
)
PET_ALT=(
'             .-----.'
'            / {1}   {2} \'
'           |    {m}    |'
'           |         |'
'           |\/\/\/\/\|'
''
)
typeset -gA PET_MOUTH=(rest "-" talk "o" open "O" sad "n" happy "u" tongue "p" grit "=" angry "#")
PET_TRICKS=("b:boo:16" "v:vanish:30" "s:spook:20" "w:wink:9" "l:look:9" "y:yay:20" "z:nap:40")
PET_IDLE=(boo spook wink look)

pet_frame() { (( alt = (tick / 4) % 2, dy = (tick / 10) % 2 )); }   # hems ripple, bobbing gently
pet_trick() {
  case $1 in
    boo)    e1='O'; e2='O'; mouth=${PET_MOUTH[open]}; bub='BOO!'; bc=$W; fc=$W; (( left > 8 )) && shx=$(( tick % 3 )) ;;
    vanish) fc=$D
            if   (( left > 20 )); then bub='...'; bc=$D
            elif (( left > 8 ));  then hide=1
            else bub='*poof*'; bc=$D; fi ;;
    spook)  e1='@'; e2='@'; mouth=${PET_MOUTH[sad]}; (( (tick / 3) % 2 )) && bub='ooOOoo' || bub='OOooOO'; bc=$M; fc=$M ;;
    *) return 1 ;;
  esac
}

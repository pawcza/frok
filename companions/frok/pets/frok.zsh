# frok — the frog. Catches flies.
PET_LABEL=frok
PET_GONE="(she left)"
PET_EYE="'"
PET_ART=(
'            _     _'
'           ({1})-=-({2})'
'         __(   "   )__'
'        / _/{m}\_ \'
'     ___\\ \\     // //___'
'     >____)/_\---/_\(____<'
)
typeset -gA PET_MOUTH=(rest "'-----'" talk "'--o--'" open "'--O--'" sad "'--u--'" happy "'\___/'"
                       tongue "'--p--'" grit "'^^^^^'" angry "'#####'")
PET_TRICKS=("f:fly:30" "w:wink:9" "g:googly:9" "l:look:9" "r:roll:12" "t:tongue:9" "y:yay:20" "x:dead:32" "d:dizzy:20" "z:nap:40")
PET_IDLE=(wink googly look roll tongue fly fly)

flx=4; fly=2
pet_start() { [[ $1 == fly ]] && { flx=$(( RANDOM % 8 + 1 )); fly=$(( RANDOM % 2 + 2 )); }; }
pet_trick() {
  case $1 in
    fly) if (( left > 8 )); then                      # a fly buzzing about, frog watching it
           flx=$(( flx + RANDOM % 3 - 1 )); (( flx < 1 )) && flx=1; (( flx > 8 )) && flx=8
           (( RANDOM % 3 == 0 )) && fly=$(( fly == 2 ? 3 : 2 ))
           marg[$fly]="${(l:$((flx - 1)):)}*"; mc[$fly]=$W; e1='o'; e2='o'
         elif (( left > 5 )); then mouth=${PET_MOUTH[open]}; e1='O'; e2='O'   # snap!
         else mouth=${PET_MOUTH[happy]}; e1='^'; e2='^'; bub='gulp'; fi ;;
    *) return 1 ;;
  esac
}

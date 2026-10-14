# cat — knocks things off the edge, purrs, hisses when poked.
PET_LABEL=cat
PET_GONE="(he left)"
PET_EYE='o'
PET_ART=(
'             /\_____/\'
'            /  {1}   {2}  \'
'           ( == {m} == )'
'            )         ('
'           (  )     (  )'
'          (__(__)___(__)__)'
)
PET_ALT=(                                     # stretching, front paws out
'             /\_____/\'
'            /  {1}   {2}  \'
'           ( == {m} == )'
'     _______)         ('
'    (_______    ___  (  )'
'           (___/   \_(__)_)'
)
typeset -gA PET_MOUTH=(rest " w " talk " o " open " O " sad " ^ " happy "\w/"
                       tongue " P " grit "^^^" angry "###")
PET_TRICKS=("k:knock:22" "s:stretch:18" "u:purr:20" "h:hiss:14" "c:chase:30" "w:wink:9" "l:look:9" "y:yay:20" "z:nap:40")
PET_IDLE=(knock stretch purr chase wink look)

dotx=4; doty=2
pet_start() { [[ $1 == chase ]] && { dotx=$(( RANDOM % 8 + 1 )); doty=$(( RANDOM % 2 + 2 )); }; }
pet_trick() {
  case $1 in
    knock)                                    # a mug on the ledge… not for long
      if   (( left > 14 )); then marg[1]="       u"; mc[1]=$W; e1='.'; e2='.'
      elif (( left > 12 )); then marg[2]="       u"; mc[2]=$W; e1='o'; e2='o'
      elif (( left > 10 )); then marg[3]="       u"; mc[3]=$W
      else bub='*crash*'; bc=$Y; e1='^'; e2='^'; mouth=${PET_MOUTH[happy]}; fi ;;
    stretch) alt=1; e1='-'; e2='-'; (( left > 8 )) && { mouth=${PET_MOUTH[open]}; bub='yawn'; bc=$D; } ;;
    purr)    (( (tick / 3) % 2 )) && { e1='^'; e2='^'; } || { e1='-'; e2='-'; }
             (( (tick / 2) % 2 )) && bub='prrr' || bub='rrrr'; bc=$D ;;
    hiss)    e1='>'; e2='<'; mouth=${PET_MOUTH[open]}; bub='hsss'; bc=$R; (( tick % 2 )) && shx=1 ;;
    chase)   if (( left > 6 )); then              # a laser dot, darting about
               dotx=$(( dotx + RANDOM % 5 - 2 )); (( dotx < 1 )) && dotx=1; (( dotx > 8 )) && dotx=8
               (( RANDOM % 3 == 0 )) && doty=$(( doty == 2 ? 3 : 2 ))
               marg[$doty]="${(l:$((dotx - 1)):)}•"; mc[$doty]=$R; e1='O'; e2='O'
             else shx=2; e1='^'; e2='^'; bub='got it'; fi ;;
    *) return 1 ;;
  esac
}

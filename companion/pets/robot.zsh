# robot — beeps, scans, reboots after an error.
PET_LABEL=robot
PET_GONE="(powered off)"
PET_EYE='o'
PET_ART=(
'               _|_'
'          .---[___]---.'
'          |  [{1}] [{2}]  |'
'          |   {m}   |'
'          `---.___.---`'
'             _|   |_'
)
PET_ALT=(                                     # antenna light on
'               _*_'
'          .---[___]---.'
'          |  [{1}] [{2}]  |'
'          |   {m}   |'
'          `---.___.---`'
'             _|   |_'
)
typeset -gA PET_MOUTH=(rest "-----" talk "--o--" open "[___]" sad "/---\\" happy "\\___/"
                       tongue "--p--" grit "^^^^^" angry "#####")
PET_TRICKS=("b:beep:16" "s:scan:20" "r:reboot:36" "d:dance:20" "w:wink:9" "y:yay:20" "x:dead:32" "z:nap:40")
PET_IDLE=(beep scan dance wink)

pet_frame() { (( tick % 25 < 2 )) && alt=1; }  # the antenna blinks now and then
pet_trick() {
  local sc=('<' '-' '>' '-')
  case $1 in
    beep)   (( tick % 2 )) && alt=1; mouth=${PET_MOUTH[talk]}; (( (tick / 3) % 2 )) && bub='beep' || bub='boop'; bc=$C ;;
    scan)   e1=${sc[(tick / 2) % 4 + 1]}; e2=$e1; alt=1 ;;
    reboot) if   (( left > 24 )); then e1='_'; e2='_'; fc=$D; bub='reboot'; bc=$D
            elif (( left > 10 )); then e1='#'; e2='#'; (( (tick / 2) % 2 )) && bub='.' || bub='..'; bc=$D
            else e1='o'; e2='o'; mouth=${PET_MOUTH[happy]}; bub='ok!'; bc=$G; fi ;;
    dance)  (( shx = (tick / 2) % 2 * 2 )); e1='^'; e2='^'; mouth=${PET_MOUTH[happy]}; bub='♪'; bc=$M; (( tick % 2 )) && alt=1 ;;
    *) return 1 ;;
  esac
}

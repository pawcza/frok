# octopus — waves, juggles, inks when poked, changes colour.
PET_LABEL=octopus
PET_GONE="(swam off)"
PET_EYE='o'
PET_ART=(
'             .-""-.'
'            / {1}  {2} \'
'           |    {m}   |'
'           \__.--.__/'
'          _/ /|  |\ \_'
'         /_ ( |  | ) _\'
)
PET_ALT=(
'             .-""-.'
'            / {1}  {2} \'
'           |    {m}   |'
'           \__.--.__/'
'           \ \|  |/ /'
'          _/ /(  )\ \_'
)
typeset -gA PET_MOUTH=(rest "-" talk "o" open "O" sad "n" happy "u" tongue "p" grit "=" angry "#")
PET_TRICKS=("a:wave:20" "j:juggle:30" "i:ink:24" "c:colour:24" "w:wink:9" "l:look:9" "y:yay:20" "z:nap:40")
PET_IDLE=(wave juggle colour wink look)

pet_frame() { (( (tick / 8) % 2 )) && alt=1; }  # tentacles sway
pet_trick() {
  local cols=($R $Y $G $C $M)
  case $1 in
    wave)   (( (tick / 2) % 2 )) && alt=1 || alt=0; bub='hi!'; bc=$C; mouth=${PET_MOUTH[happy]} ;;
    juggle) e1='.'; e2='.'                       # three balls, up and down
            local p=$(( tick % 3 ))
            marg[$(( p + 1 ))]="     o"; marg[$(( (p + 1) % 3 + 1 ))]="       o"; marg[$(( (p + 2) % 3 + 1 ))]="   o"
            mc=($Y $C $M) ;;
    ink)    e1='>'; e2='<'; mouth=${PET_MOUTH[open]}
            marg[2]="  %%%%%%"; marg[3]=" %%%%%%%"; mc[2]=$D; mc[3]=$D; (( left > 16 )) && { bub='pfft'; bc=$D; } ;;
    colour) fc=${cols[(tick / 3) % 5 + 1]}; bub='~'; bc=$fc ;;
    *) return 1 ;;
  esac
}

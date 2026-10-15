# clock — the time and date, plus world clocks. Options: zones ("Tokyo=Asia/Tokyo, New York=America/New_York"), format (24h or 12h).
# options: zones format
W_LABEL[clock]=clock

w_clock_render() {
  local fmt='%H:%M' z name tz row
  [[ $(wopt clock format 24h) == 12h ]] && fmt='%I:%M %p'
  row="${W}"$'\e[1m'"$(strftime $fmt $EPOCHSECONDS)${X}  ${D}$(strftime '%a %e %b' $EPOCHSECONDS)${X}"
  for z in ${(s:,:)$(wopt clock zones "")}; do
    z=${z## }; z=${z%% }; [[ $z == *=* ]] || continue
    name=${z%%=*}; tz=${z#*=}
    [[ -e /usr/share/zoneinfo/$tz || -e /var/db/timezone/zoneinfo/$tz ]] || continue   # a typo'd zone would read as UTC
    row+="     ${ACC}${name}${X} $( local TZ=$tz; strftime $fmt $EPOCHSECONDS )"
  done
  wl=("$row")
}

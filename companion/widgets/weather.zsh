# weather — now and today, from Open-Meteo (free, no key). Options: city (required), units (metric or imperial).
# options: city units
W_LABEL[weather]=weather

w_weather_refresh() {
  local city=$(wopt weather city "") f=$WSTATE/weather.json
  [[ -n $city && -z ${FROK_DEMO-} ]] || return
  local -a m r; zstat -A m +mtime -- $f 2>/dev/null; zstat -A r +mtime -- $f.retry 2>/dev/null
  # every 15 minutes, or right away when the city or units change
  [[ -f $f && $(jq -r '.city + "|" + .units' $f 2>/dev/null) == "$city|$(wopt weather units metric)" ]] \
    && (( EPOCHSECONDS - ${m[1]:-0} < 900 )) && return
  # after a failed request, give the service a minute before asking again
  (( EPOCHSECONDS - ${r[1]:-0} < 60 )) && return
  [[ -e $f.lock ]] && return; : >| $f.lock
  {
    local units=$(wopt weather units metric) q geo lat lon place tu wu
    [[ $units == imperial ]] && { tu=fahrenheit; wu=mph; } || { tu=celsius; wu=kmh; }
    q=$(jq -rn --arg c "$city" '$c | @uri')
    # A failed request says nothing about the city: keep what we have and try again.
    geo=$(curl -fs --max-time 8 "https://geocoding-api.open-meteo.com/v1/search?name=$q&count=1") || { : >| $f.retry; rm -f $f.lock; return }
    lat=$(jq -r '.results[0].latitude // empty' <<< $geo); lon=$(jq -r '.results[0].longitude // empty' <<< $geo)
    place=$(jq -r '.results[0].name // empty' <<< $geo)
    if [[ -n $lat ]]; then
      local forecast=$(curl -fs --max-time 8 "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&timezone=auto&forecast_days=1&temperature_unit=$tu&wind_speed_unit=$wu&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m,is_day&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max")
      if [[ -n $forecast ]]; then
        jq --arg city "$city" --arg units "$units" --arg place "$place" '. + {city: $city, units: $units, place: $place}' <<< $forecast > $f.tmp \
          && mv -f $f.tmp $f && rm -f $f.retry
      else
        : >| $f.retry
      fi
    else
      jq -n --arg city "$city" --arg units "$units" '{city: $city, units: $units, error: "no such place"}' > $f
    fi
    rm -f $f.lock $f.tmp
  } &!
}

# WMO weather codes → a Nerd Font weather icon (one cell wide, unlike emoji) and a word
w_weather_says() {   # w_weather_says <code> <is day>
  case $1 in
    0)    (( $2 )) && print -rn -- $'\ue30d clear' || print -rn -- $'\ue32b clear' ;;
    1|2)  print -rn -- $'\ue302 partly cloudy' ;;          3) print -rn -- $'\ue312 cloudy' ;;
    45|48) print -rn -- $'\ue313 fog' ;;                    51|53|55|56|57) print -rn -- $'\ue31b drizzle' ;;
    61|63|65|66|67|80|81|82) print -rn -- $'\ue318 rain' ;; 71|73|75|77|85|86) print -rn -- $'\ue31a snow' ;;
    95|96|99) print -rn -- $'\ue31d thunderstorm' ;;        *) print -rn -- "· —" ;;
  esac
}

w_weather_render() {
  local f=$WSTATE/weather.json city=$(wopt weather city "")
  if [[ -z $city ]]; then wl=("${D}set your city: ${W}frok dashboard set weather city <name>${X}"); return; fi
  if [[ ! -s $f ]]; then wl=("${D}fetching the weather for $(clean "$city")…${X}"); return; fi
  local -a v=("${(@f)$(jq -r '.error // "", (.current.temperature_2m|round), (.current.apparent_temperature|round), .current.weather_code,
      (.daily.temperature_2m_max[0]|round), (.daily.temperature_2m_min[0]|round), (.daily.precipitation_probability_max[0] // 0),
      (.current.wind_speed_10m|round), .place // .city, .current_units.wind_speed_10m // "", (.current.is_day // 1)' $f 2>/dev/null)}")
  if [[ -n ${v[1]} ]]; then wl=("${R}$(clean "$city"): ${v[1]}${X}"); return; fi
  local says=$(w_weather_says ${v[4]} ${v[11]:-1})
  wl=("${Y}${says%% *}${X} ${W}"$'\e[1m'"${v[2]}°${X}${D} feels ${v[3]}° · ${says#* } · ↑${v[5]}° ↓${v[6]}° · rain ${v[7]}% · wind ${v[8]} $(clean "${v[10]}") · ${X}${ACC}$(clean "${v[9]}")${X}")
}

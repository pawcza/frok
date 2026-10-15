# system — CPU, memory, disk and (on laptops) battery. Option: disk (the path to measure, default /).
# options: disk
W_LABEL[system]=system

w_sys=(); w_sys_cpu_prev=""
w_system_refresh() {
  (( tick % 10 == 0 )) || (( ! ${#w_sys} )) || return      # every ~2 s
  local cpu="" mem="" disk="" bat="" l t u
  if [[ -r /proc/stat ]]; then                              # Linux, WSL
    local -a f=(${=${(M)${(f)"$(</proc/stat)"}:#cpu *}})
    (( t = f[2] + f[3] + f[4] + f[5] + f[6] + f[7] + f[8] + f[9], u = t - f[5] - f[6] ))
    [[ -n $w_sys_cpu_prev ]] && { local -a p=(${=w_sys_cpu_prev}); (( t > p[1] )) && cpu=$(( (u - p[2]) * 100 / (t - p[1]) )); }
    w_sys_cpu_prev="$t $u"
    local -A mi; for l in ${(f)"$(</proc/meminfo)"}; do mi[${l%%:*}]=${${l#*:}//[^0-9]/}; done
    (( ${mi[MemTotal]:-0} )) && mem=$(( (mi[MemTotal] - mi[MemAvailable]) * 100 / mi[MemTotal] ))
    for l in /sys/class/power_supply/BAT*/capacity(N); do bat=$(<$l); break; done
  elif [[ $OSTYPE == darwin* ]]; then                        # macOS
    local n=$(sysctl -n hw.ncpu 2>/dev/null) s=0
    for l in ${(f)"$(ps -A -o %cpu= 2>/dev/null)"}; do (( s += l )); done
    (( n )) && cpu=$(( int(s / n) ))
    l=$(memory_pressure 2>/dev/null | grep -o 'free percentage: [0-9]*'); [[ -n $l ]] && mem=$(( 100 - ${l##* } ))
    bat=$(pmset -g batt 2>/dev/null | grep -o '[0-9]*%' | head -1); bat=${bat%\%}
  fi
  (( tick % 150 == 0 || ! ${#w_sys} )) && w_sys_disk=$(df -P $(wopt system disk /) 2>/dev/null | awk 'NR==2 {print $5+0}')
  w_sys=("$cpu" "$mem" "${w_sys_disk-}" "$bat")
}

w_system_render() {
  local row="" i; local -a names=(cpu mem disk bat)
  for i in 1 2 3 4; do
    [[ -n ${w_sys[i]} ]] || continue
    row+="${row:+     }${D}${names[i]} ${X}$(bar ${w_sys[i]})"
  done
  wl=("${row:-${D}measuring…${X}}")
}

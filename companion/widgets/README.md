# Dashboard widgets

Everything under the sessions in the companion is a widget. Which ones show,
and in what order, is the `dashboard` list in `~/.config/frok/frok.json`.
Change it with `frok dashboard` or in `frok menu` › dashboard; open companions
pick the change up within a second.

| Widget | Shows | Options (`frok dashboard set <widget> <option> <value>`) |
|---|---|---|
| `clock` | time, date, world clocks | `zones` ("Tokyo=Asia/Tokyo, New York=America/New_York"), `format` (24h / 12h) |
| `weather` | now and today, from Open-Meteo | `city`, `units` (metric / imperial) |
| `news` | Hacker News or RSS / Atom headlines; `N` next, click to open | `feeds` ("hn" and/or feed URLs), `lines` (1–3) |
| `system` | CPU, memory, disk, battery | `disk` (path, default /) |
| `timer` | focus timer; `T` starts / stops | `minutes` (25), `break` (5) |
| `fact` | a useless fact; space for another | |
| `stats` | tokens, lines, commits; `p` switches today / 7 / 30 days | |
| `limits` | 5-hour and 7-day usage limits | |
| `keys` | the settings button and pane shortcuts | |
| `tricks` | the pet's tricks | |

The default dashboard is `fact stats limits keys tricks`.

The weather icons come from Nerd Fonts (frok's fonts all have them).
Weather and news are fetched in the background (every 15 minutes) and cached
in `~/.local/state/frok/companion/widgets/`. Text from the internet is
stripped of control characters before it reaches the terminal, and links only
open if they're http(s).

## Writing one

A widget is one file, `<name>.zsh`, sourced by the companion:

```zsh
# name — what it shows; keys and clicks. Options: what you can set.
# options: opt1 opt2
W_LABEL[name]=label          # the chip on the left (≤ 7 characters)
W_KEYS[X]=name               # optional: a key it owns (capitals; pets use lowercase)

w_name_init()    { … }       # optional: when the dashboard (re)loads
w_name_refresh() { … }       # optional: every frame (~5/s); decide your own pace with $tick,
                             # and fetch in the background (… &!) into $WSTATE
w_name_render()  {           # required: fill wl with lines at most $cw wide
  wl=("${W}hello${X} ${D}world${X}")
  wclick+=("1:1:5:greet")    # optional: "line:x0:x1:action", x counted from the line's start
}
w_name_click()   { … }       # optional: $1 is the action of what was clicked
w_name_key()     { … }       # optional: $1 is the key
```

Available to widgets: `wopt <widget> <option> <default>`, colours (`$G $Y $R $C
$M $L $D $W $X`, chips `$KB`, accent `$ACC`), `bar <percent>`, `human <n>`,
`dur <seconds>`, `cut_to <text> <width>`, `pack <width> <items…>`,
`clean <text>` (always use it on text from the internet), `open_url`,
`notify <title> <text>`, and `start_ev yay 20` to make the pet react.
`tests/run.sh widgets` checks every widget file.

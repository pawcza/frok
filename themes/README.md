# Themes

A theme is one JSON file. frok looks in `~/.config/frok/themes/` first, then
here, so a file of your own with the same name wins. `frok theme <file name>`
applies it.

```json
{
  "name": "Tokyo Night",
  "bg": "#1a1b26", "fg": "#c0caf5", "cursor": "#c0caf5", "selection": "#33467c",
  "ansi":    ["#15161e", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6"],
  "brights": ["#414868", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5"],
  "ui": { "surface": "#16161e", "muted": "#565f89", "accent": "#7aa2f7", "accent2": "#bb9af7", "border": "#3b4261", "hover": "#292e42" }
}
```

| Key | Used for |
|---|---|
| `bg` `fg` `cursor` `selection` | the terminal |
| `ansi`, `brights` | the 16 terminal colours: black, red, green, yellow, blue, magenta, cyan, white |
| `ui.surface` | bands and bars in the setup screens |
| `ui.muted` | secondary text |
| `ui.accent`, `ui.accent2` | highlights, the logo gradient, the companion's label text |
| `ui.border` | the companion's label chips and the frame around the pet |
| `ui.hover` | key chips and inactive tabs |

The rain background is recoloured from the theme, so a new theme gets its own
rain.

# frok

A terminal upgrade you set up once and then steer by asking. One command
installs what it needs, and Claude Code walks you through the choices:
colour theme, animated background, a pet that watches your Claude Code
sessions, pane layouts, prompt, font, CLI tools. Run `frok` again any time to
change something.

```
    hey!    _     _            ● frok        working      Edit wezterm.lua      4s
           (')-=-(-)           ● persona     needs you    needs permission: $ npm run dev
         __(   "   )__         ● spot        background   2 background tasks running
        / _/'-----'\_ \        ✶ The dot over the letter "i" is called a tittle.   space → new fact
     ___\\ \\     // //___     Alt+D split→  Alt+⇧D split↓  Alt+←↑↓→ move  Ctrl+⇧W close pane
     >____)/_\---/_\(____<     frog: f fly  w wink  g googly  l look  r roll  t tongue  y yay  x dead
```

## Install

```sh
git clone https://github.com/pawcza/frok && ./frok/install.sh
```

The installer gets `git curl jq zsh unzip` with your package manager (Homebrew,
apt, dnf, pacman, zypper, apk — installing Homebrew first on a bare Mac), puts
`frok` in `~/.local/bin`, and starts the setup: six steps in the terminal
(theme, background, companion, layout, prompt, font), each applied as you pick
it, then an offer to keep going with Claude Code. It asks for your password only
when the system needs it. Everything else — fonts, CLI tools, starship,
Pillow for the backgrounds, Claude Code hooks — frok installs itself when you
pick it.

On Windows, run it inside WSL (Ubuntu). frok configures Windows Terminal and
WezTerm on the Windows side from there, and installs fonts for your Windows
user (no admin needed).

## Using it

`frok` opens the guide: Claude Code with the `frok` skill, which asks what you
want and runs the commands below. `frok setup` runs the step-by-step setup
again. Every choice also has a direct command:

| | |
|---|---|
| `frok theme [name]` | colour theme for the terminal, prompt, fzf and companion — tokyo-night, catppuccin-mocha, gruvbox-dark, dracula, matrix |
| `frok background rain\|none\|<file>` | seamless digital rain recoloured to the theme, any image or GIF, or nothing · `frok background opacity 0.2` |
| `frok companion frog\|none` | the session pet · `frok companion facts on\|off` |
| `frok layout [name]` | `single`, `side`, `quad` (the MacBook one), `grid` · `frok layout open` · `frok layout autostart on` |
| `frok agent "<cmd>"` | what agent panes run (default `claude`, e.g. `ccs personal`) · `frok workdir ~/dev` |
| `frok prompt starship\|none` | |
| `frok font "<family>" [size]` | Nerd Fonts download automatically |
| `frok tools [install\|add\|remove]` | eza, bat, fd, zoxide, ripgrep, fzf, delta, lazygit, gh, btop, tldr, zsh-autosuggestions |
| `frok terminals [set …\|auto]` | which terminals to configure (detected by default) |
| `frok status`, `frok doctor`, `frok apply`, `frok update`, `frok uninstall` | |

Your own themes and layouts go in `~/.config/frok/themes/*.json` and
`~/.config/frok/layouts/*.json` (copy one from this repo). Settings live in
`~/.config/frok/frok.json`.

## Terminals

| | Theme, font, keys | Background | Layouts | Companion: click to jump |
|---|---|---|---|---|
| **WezTerm** (macOS, Linux, Windows) | ✓ | animated, tiled | on start | ✓ |
| **Windows Terminal** (from WSL) | ✓ | animated | on start, `frok layout open`, Ctrl+⇧L | — |
| **kitty** | ✓ | — | — | ✓ |
| anything else | prompt, tools, companion | — | — | — |

The same pane keys everywhere: ⌘ on macOS, Alt elsewhere — split right
(⌘D / Alt+D), split down (+⇧), move (⌘⌥ / Alt + arrows), resize (⌘⇧ / Alt+⇧ +
arrows), close (⌘⇧W / Ctrl+⇧W), zoom (⌘Z / Alt+Z), companion pane (⌘⇧K /
Ctrl+⇧K).

## What frok touches

frok owns its own files and marked blocks and keeps backups:

- one line in `~/.zshrc` / `~/.bashrc` that sources `~/.config/frok/generated/init.sh`
- WezTerm: `wezterm.lua` (yours is kept as `wezterm.lua.pre-frok`; personal
  tweaks go in `frok-local.lua`)
- Windows Terminal: a `frok <theme>` scheme, a hidden `frok companion` profile,
  `User.frok.*` actions and keys, and the look of your WSL profile (originals
  saved, `frok uninstall` puts them back; a backup of every write in
  `~/.local/state/frok/backups`)
- kitty: `frok.conf`, included from `kitty.conf`
- Claude Code: the companion hook and the `frok` skill in every config dir
  (`~/.claude`, `$CLAUDE_CONFIG_DIR`, ccs profiles)

## The companion

`companion-event.sh` is a Claude Code hook. For each event it writes one line
per session to `~/.local/state/frok/companion/sessions/<id>`: time, state,
pane, folder, and a short description (the file being edited, the command
running). It never stores full prompts, file contents or output, and always
exits 0 so it can't slow Claude down. The frog's face follows the most urgent
session: needs you → wide eyes, error → x_x, working → squinting, done → yay.
Poke her a few times and she leaves for a bit.

`docs/` keeps the original MacBook setup notes this grew out of.

# frog-companion

A tiny terminal pet that keeps an eye on your Claude Code sessions.

```
    hey!    _     _            ● Upgrade terminal with animations…   working      Edit wezterm.lua      4s
           (')-=-(-)           ● Set up persona project              needs you    needs permission: $ npm run dev
         __(   "   )__         ● Find song with seize to exist…      background   2 background tasks running
        / _/'-----'\_ \        ✶ The dot over the letter "i" is called a tittle.   space → new fact
     ___\\ \\     // //___     ⌘D split→  ⌘⇧D split↓  ⌘⌥←↑↓→ move  ⌘⇧W close pane
     >____)/_\---/_\(____<     frog: f fly  w wink  g googly  l look  r roll  t tongue  y yay  x dead  d dizzy  z nap
```

Run `companion` in a spare pane. It lists every Claude Code session with what
it's doing right now (the file it's editing, the command it's running, the
prompt you gave it), and the frog's face follows the most urgent one:

| Session state | Frog |
|---|---|
| needs you (permission prompt / question) | wide `O O` eyes, open mouth, flashing `!` |
| error | `x x` eyes, tongue out, `x_x`, a shiver |
| working | squinting `> <`, moving mouth, spinner |
| thinking | drifting eyes, `?` `..` `...` |
| compacting | spinning `@ o O` eyes |
| background tasks still running | calm, `..` |
| just finished | `^ ^`, smile, "yay!" and sparkles |
| nothing for 10 minutes | asleep, `z Z z` |

When nothing's going on she does random tricks (winks, googly eyes, eye rolls,
tongue, hunting a fly), and she doesn't like being poked: click her a few times
and she gets annoyed, then angry, then she leaves for a bit.

## Keys and mouse

| | |
|---|---|
| `space` | new useless fact ([uselessfacts.jsph.pl](https://uselessfacts.jsph.pl/)) |
| `f w g l r t y x d z` | tricks: fly, wink, googly, look, roll, tongue, yay, dead, dizzy, nap |
| click a session | jump to its pane (WezTerm, kitty) |
| click the frog | annoy her |
| `Ctrl+C` | quit |

## Install

Needs `zsh`, `jq`, `curl` (and `fold`, which every system has).

```sh
git clone git@github.com:pawcza/frog-companion.git
cd frog-companion
./install.sh
```

This copies the scripts to `~/.config/terminal`, links a `companion` command
into `~/.local/bin`, and adds a hook to `~/.claude/settings.json` for the
Claude Code events the companion listens to. Your existing hooks are kept, and
a backup of `settings.json` is saved next to it. Run it again to update;
`./install.sh --uninstall` removes the hooks and the command.

Sessions that were already running pick up the hook the next time they do
something.

If you use several Claude Code config directories (e.g. with `ccs` profiles),
point the installer at the right one: `CLAUDE_SETTINGS=/path/to/settings.json ./install.sh`.

## Terminals

| | Session names | Click to jump | |
|---|---|---|---|
| **WezTerm** | pane titles | ✅ | `wezterm cli` |
| **kitty** | window titles | ✅ | needs `allow_remote_control` + `listen_on` |
| **anything else** (Windows Terminal + WSL, iTerm, Terminal.app…) | the session's folder | — | found by tty |

Works on macOS, Linux and WSL, as long as Claude Code runs on the same machine
as the companion (inside WSL, not on the Windows side).

## How it works

`companion-event.sh` is the Claude Code hook. For each event it writes one line
per session to `sessions/<session id>`: the time, a state, which pane it's in,
the folder, and a short description of what it's doing. It never stores prompts
in full, file contents or command output, and it always exits 0 so it can't
slow down or block Claude. `claude-companion.sh` reads those files, works out
which panes are still running Claude, and draws the frog.

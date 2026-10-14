# The companion

One engine and a choice of pets. Claude Code tells it what each session is
doing; the terminal tells it where the sessions live.

```
Claude Code ──hooks──────▶ companion-event.sh ──▶ state/companion/sessions/<id>
            ──status line▶ statusline.sh ───────▶ state/companion/status/<id>
transcripts ─────────────▶ stats.sh (every minute) ▶ state/companion/stats/days.json
                                                         │
terminal (panes, ttys) ──────────────────────────▶ claude-companion.sh ◀── pets/<pet>.zsh
```

State lives in `~/.local/state/frok/companion/`.

| File | What it does |
|---|---|
| `claude-companion.sh` | the pane: finds sessions, draws the pet, the session list and the footer, handles keys and clicks |
| `companion-event.sh` | a Claude Code hook for every event (prompt, tool use, permission, stop…). Writes one line per session: time, state, pane, folder, what it's doing, its title, the transcript path. Never stores prompts, file contents or output, and always exits 0. |
| `statusline.sh` | Claude Code's status line command. Keeps the session's context % and the 5-hour / 7-day usage limits, and prints a short line in Claude Code |
| `stats.sh` | indexes every transcript into per-day tokens, lines added/removed (from edits) and commits (successful `git commit` calls). Reads only new bytes after the first run. |
| `pets/` | the pets: art, faces, tricks ([format](pets/README.md)) |
| `frog.txt` | the frok mascot in the setup screens' banner |

## Where a session's status comes from

1. **The hook** reports each event as it happens.
2. **The transcript** overrules it. If the last turn ended (or was interrupted),
   the session is done, even when a late hook, such as a background subagent
   finishing, said otherwise.
3. **The status line** gives the exact context % (the transcript gives an
   estimate until it arrives).

## Finding panes

- **WezTerm / kitty:** their CLI lists panes, titles and the focused one.
- **Windows Terminal (WSL):** sessions are found by tty. The layout starts each
  pane with `FROK_PANE=<n>`, its pane id, so a click can run
  `wt.exe focus-pane -t <n>`. A companion opened by the layout only shows
  sessions whose panes started with it (within 30 s), so other tabs stay out.
  Windows Terminal doesn't say which pane has focus, so "current" is the pane
  you last typed in.

## Demo mode

`FROK_DEMO=1` makes the companion take its sessions only from the state files,
skipping the process scan. `docs/screenshots/make.sh` uses this to draw the
README screenshots from made-up sessions.

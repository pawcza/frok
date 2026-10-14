# Layouts

A layout is a list of panes. The first pane is the whole tab; every pane after
it splits an earlier one. frok looks in `~/.config/frok/layouts/` first, then
here. `frok layout <file name>` picks one.

```json
{
  "name": "side",
  "about": "Agent on the left half; right half split into companion on top, a shell below.",
  "panes": [
    { "id": "main",  "name": "left",         "run": "agent" },
    { "id": "pet",   "name": "top right",    "split": "main", "dir": "right", "size": 0.5, "run": "companion" },
    { "id": "shell", "name": "bottom right", "split": "pet",  "dir": "down",  "size": 0.5, "run": "shell" }
  ],
  "focus": "main"
}
```

| Pane key | |
|---|---|
| `id` | how other panes refer to it |
| `name` | shown in `frok menu` › layout › Panes |
| `split`, `dir`, `size` | which pane it splits, `right` or `down`, and the new pane's share (0–1) |
| `run` | `agent` (your `frok agent` command), `companion`, `shell`, or any command |

`focus` is the pane that has the cursor when the layout opens. What a pane runs
and which folder it starts in can be changed per layout in `frok menu` without
editing the file (saved in `frok.json` under `panes`).

| Built in | |
|---|---|
| `single` | one agent |
| `side` | agent on the left; companion and a shell on the right |
| `quad` | companion strip, shell and agent on the left; two agents on the right |
| `grid` | a companion strip across the top, four agents below |

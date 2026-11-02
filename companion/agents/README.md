# Agents

The companion doesn't need an agent, and doesn't need one to cooperate. Any
pane running a process it recognises gets a row. An agent that can report its
state gets a live one.

| File | What it does |
|---|---|
| `agents.sh` | `agent_of`: which agent a process is, looking through `node` and `python`. `agent_label`: its display name |
| `<agent>.jq` | turns the agent's hook payload into the fields `companion-event.sh` reads |
| `opencode-plugin.js` | opencode has plugins rather than hooks. frok writes this into its plugins folder |
| `../../lib/agents/<agent>.zsh` | connecting it: where its config lives, adding and removing frok's entries |

## The vocabulary

A `.jq` file ends in one array:

```
[ event, session id, folder, tool, tool's target, prompt, message, notification type, transcript path, title ]
```

Events are Claude Code's names, plus two of frok's own:

| Event | State |
|---|---|
| `SessionStart` | idle |
| `UserPromptSubmit` | thinking; the prompt names the session |
| `PreToolUse`, `SubagentStart` | working |
| `PostToolUse`, `SubagentStop` | thinking |
| `PostToolUseFailure`, `Error` (frok's) | error |
| `PermissionRequest`, `Notification` | needs you |
| `PreCompact` | compacting |
| `Busy` (frok's) | thinking, keeping what it last said |
| `Stop` | done |
| `SessionEnd` | removed |

Anything else is ignored. Tool names `Bash`, `Edit`, `Write`, `Read`, `Grep`,
`Glob`, `WebFetch` and `WebSearch` get a nice description, so map onto those
where you can.

## Adding one

1. Add its process name to `agent_of` and its name to `agent_label`.
2. If it has hooks, add `<agent>.jq` and add it to the `case` at the top of
   `companion-event.sh`.
3. Add `lib/agents/<agent>.zsh` with `agent_<id>_present`, `_connect on|off`,
   `_connected`, `_command` and `AGENT_FEATURES[<id>]`, then add the id to
   `AGENTS` in `lib/agents.zsh`.
4. Add a fixture in `tests/fixtures/agents/` that follows the agent's own format,
   a test in `tests/run.sh`, and an honest row in the README's table.

Only step 1 is needed for a row showing `running`, and `frok agents watch
<command>` does that one without touching the code.

Hooks must stay observers: exit 0, print nothing, and never take part in a
permission decision.

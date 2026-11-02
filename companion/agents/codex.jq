# Codex hooks (https://learn.chatgpt.com/docs/hooks). Same event names as Claude
# Code, plus Interrupt and PostCompact. Shell runs arrive as Bash, every file
# edit as apply_patch with the patch in tool_input.command.
(.tool_name // "") as $t
| (if $t == "apply_patch" then "Edit" else $t end) as $tool
| [ ( .hook_event_name | if . == "Interrupt" then "Stop" elif . == "PostCompact" then "Busy" else . end ),
    .session_id, .cwd, $tool,
    ( if $t == "Bash" then .tool_input.command
      elif $t == "apply_patch" then
        ((.tool_input.command // "") | tostring | [capture("\\*\\*\\* (Update|Add|Delete) File: (?<f>[^\n]+)")] | .[0].f)
      else "" end ),
    .prompt, .message, "", .transcript_path, "" ]

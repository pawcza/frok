# Claude Code hook payloads are the vocabulary the other agents map onto.
[ .hook_event_name, .session_id, .cwd, .tool_name,
  ( .tool_input as $i | (.tool_name // "") as $t |
    if   $t == "Bash" then $i.command
    elif ($t | test("^(Edit|MultiEdit|Write|Read|NotebookEdit)$")) then ($i.file_path // $i.notebook_path)
    elif ($t == "Grep" or $t == "Glob") then $i.pattern
    elif $t == "WebFetch" then $i.url
    elif $t == "WebSearch" then $i.query
    elif ($t == "Task" or $t == "Agent") then $i.description
    else "" end ),
  .prompt, .message, .notification_type, .transcript_path, "" ]

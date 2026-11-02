# Gemini CLI hooks (https://geminicli.com/docs/hooks/reference/). Notification
# only ever means a tool wants permission. A failed tool still ends in AfterTool,
# with tool_response.error set.
(.tool_name // "") as $t
| .tool_input as $i
| { run_shell_command: "Bash", read_file: "Read", write_file: "Write", replace: "Edit",
    grep_search: "Grep", glob: "Glob", web_fetch: "WebFetch", google_web_search: "WebSearch" }[$t] as $tool
| [ ( .hook_event_name as $e
      | if   $e == "BeforeAgent" then "UserPromptSubmit"
        elif $e == "AfterAgent"  then "Stop"
        elif $e == "BeforeTool"  then "PreToolUse"
        elif $e == "AfterTool"   then (if .tool_response.error? then "PostToolUseFailure" else "PostToolUse" end)
        elif $e == "PreCompress" then "PreCompact"
        else $e end ),
    .session_id, .cwd, ($tool // $t),
    ( if   $t == "run_shell_command" then $i.command
      elif ($t | test("^(read_file|write_file|replace)$")) then $i.file_path
      elif ($t == "grep_search" or $t == "glob") then $i.pattern
      elif $t == "web_fetch" then $i.prompt
      elif $t == "google_web_search" then $i.query
      else "" end ),
    .prompt, .message, "", .transcript_path, "" ]

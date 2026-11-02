# What companion/agents/opencode-plugin.js forwards: opencode's own bus events
# as {event, directory, title}, and its tool hooks as {tool, directory, title}.
def tool_name:
  { bash: "Bash", read: "Read", edit: "Edit", write: "Write", grep: "Grep", glob: "Glob",
    webfetch: "WebFetch", websearch: "WebSearch", task: "Task" }[.] // .;
def tool_target($a):
  if   . == "bash" then $a.command
  elif (. == "read" or . == "edit" or . == "write") then $a.filePath
  elif (. == "grep" or . == "glob") then $a.pattern
  elif . == "webfetch" then $a.url
  elif . == "websearch" then $a.query
  elif . == "task" then $a.description
  else "" end;
. as $in
| ( if .tool then
      [ (if .tool.phase == "before" then "PreToolUse" else "PostToolUse" end),
        .tool.sessionID, (.tool.name | tool_name), (.tool.name | tool_target($in.tool.args // {})), "" ]
    else
      (.event.properties // {}) as $p
      | [ ( .event.type as $e
            | if   $e == "session.created" then "SessionStart"
              elif $e == "session.deleted" then "SessionEnd"
              elif $e == "session.idle"    then "Stop"
              elif $e == "session.error"   then "Error"
              elif $e == "permission.asked" then "PermissionRequest"
              elif $e == "session.status" then (if $p.status.type == "idle" then "Stop" else "Busy" end)
              else "Busy" end ),
          ($p.sessionID // $p.info.id),
          (($p.permission // "") | tool_name),
          (($p.patterns // [])[0] // ""),
          (if .event.type == "session.error" then $p.error.name
           elif $p.status.type == "retry" then "retrying: \($p.status.message)" else "" end) ]
    end ) as [$ev, $sid, $tool, $target, $msg]
| [ $ev, $sid, .directory, $tool, $target, "", $msg, "", "", .title ]

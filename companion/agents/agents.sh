# agents.sh: which coding agent a process is. Sourced by the companion (zsh)
# and by the hook (bash), so it stays plain sh.

# agent_of <process args…> → sets AGENT_ID (empty: not an agent). Interpreters
# are looked through: `node …/gemini.js`, `python -m aider`.
agent_of() {
  AGENT_ID=""
  _agent_cmd=${1##*/}; _agent_cmd=${_agent_cmd#.}
  case $_agent_cmd in
    node|nodejs|bun|deno|python|python3|python3.*)
      shift
      while [ $# -gt 0 ]; do
        case $1 in -m) shift; break ;; -*) shift ;; *) break ;; esac
      done
      case ${1:-} in
        *claude-code/cli.js) AGENT_ID=claude; return ;;
      esac
      _agent_cmd=${1##*/}; _agent_cmd=${_agent_cmd%.js} ;;
  esac
  case $_agent_cmd in
    claude|codex|gemini|opencode|aider|agy) AGENT_ID=$_agent_cmd ;;
    *) case " ${FROK_AGENT_WATCH:-} " in *" $_agent_cmd "*) AGENT_ID=$_agent_cmd ;; esac ;;
  esac
}

# agent_label <id> → AGENT_LABEL, the name people know it by (a watched command
# is its own name)
agent_label() {
  case $1 in
    claude)   AGENT_LABEL="Claude Code" ;;
    codex)    AGENT_LABEL="Codex" ;;
    gemini)   AGENT_LABEL="Gemini CLI" ;;
    opencode) AGENT_LABEL="opencode" ;;
    aider)    AGENT_LABEL="aider" ;;
    agy)      AGENT_LABEL="Antigravity" ;;
    *)        AGENT_LABEL=$1 ;;
  esac
}

// frok companion: tells the companion what opencode is doing. Managed by frok;
// `frok agents off opencode` removes it. No dependencies, and it never throws
// into opencode: a failed report is dropped.
import { spawn } from "node:child_process"

const SCRIPT = "__FROK_EVENT__"
const FORWARD = new Set(["session.created", "session.deleted", "session.status", "session.idle",
  "session.error", "session.compacted", "permission.asked", "permission.replied"])

// One at a time, so a report can't overtake the one before it.
let queue = Promise.resolve()
function send(payload) {
  queue = queue.then(() => new Promise((done) => {
    try {
      const child = spawn(SCRIPT, ["opencode"], { stdio: ["pipe", "ignore", "ignore"] })
      child.on("error", done)
      child.on("close", done)
      child.stdin.on("error", () => {})
      child.stdin.end(JSON.stringify(payload))
    } catch { done() }
  }))
}

export const FrokCompanion = async ({ directory }) => {
  const titles = new Map()
  const subagents = new Set()             // a subagent's session isn't a session of yours
  const title = (id) => titles.get(id) ?? ""
  const note = (info) => {
    if (!info?.id) return
    if (info.parentID) subagents.add(info.id)
    if (info.title && !info.title.startsWith("New session")) titles.set(info.id, info.title)
  }
  return {
    event: async ({ event }) => {
      const p = event.properties ?? {}
      if (event.type === "session.created" || event.type === "session.updated") note(p.info)
      const id = p.sessionID ?? p.info?.id
      if (!FORWARD.has(event.type) || subagents.has(id)) return
      send({ event, directory, title: title(id) })
    },
    "tool.execute.before": async (input, output) => {
      if (subagents.has(input.sessionID)) return
      send({ tool: { phase: "before", name: input.tool, sessionID: input.sessionID, args: output.args }, directory, title: title(input.sessionID) })
    },
    "tool.execute.after": async (input) => {
      if (subagents.has(input.sessionID)) return
      send({ tool: { phase: "after", name: input.tool, sessionID: input.sessionID }, directory, title: title(input.sessionID) })
    },
  }
}

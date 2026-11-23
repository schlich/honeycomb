# honeycomb-mcp: the `honeycomb` command (honeycomb.nu) as an MCP server, so
# an agent can count what it has open before it starts another topic.
#
# It speaks MCP's stdio transport: one JSON-RPC message per line on stdin,
# one per line on stdout. Each tool runs the command in a process of its own,
# so what the command prints never mixes with the protocol.
#
# $env.HONEYCOMB_SCRIPT is the command's script (the installed one sets it);
# it runs with the same `nu` as this server. A tool's `directory` argument
# defaults to the directory the server started in, which is the project an
# MCP client opened.

const protocol = "2025-06-18"

def tool [name: string, description: string, properties: record, annotations: record] {
  {
    name: $name
    description: $description
    inputSchema: { type: object, properties: $properties, additionalProperties: false }
    annotations: $annotations
  }
}

const directory = { type: string, description: "The repository to look at (default: the server's working directory)." }
const read_only = { readOnlyHint: true, openWorldHint: false }

# Five tools, one per subcommand an agent should reach without a terminal.
def tools [] {
  [
    (tool census "Count this repository's open topics (branches trunk does not hold yet), worktrees, open luvus tasks and workspaces, and Claude's live sessions per area, against the limit of six. Check it before starting a topic: a collection over six means finish, park or abandon one first. Returns JSON." { directory: $directory } $read_only)
    (tool prune "The branches trunk already holds, with their worktrees. With yes: true, removes them, their worktrees and the luvus workspaces open on them, leaving any worktree with uncommitted work or in use." {
      directory: $directory
      yes: { type: boolean, description: "Remove them instead of listing them." }
    } { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false })
    (tool sessions "Each area's live Claude sessions, most recently active first, each marked `gone` when its directory no longer exists and `beyond` when it is past the sixth of its area. Returns JSON." {} $read_only)
    (tool sidebar "The Claude desktop sidebar refiled under the seven areas: each area's live sessions, which sections it absorbs, and which stay. A plan only; `honeycomb sidebar --apply` writes it with the app closed." {} $read_only)
    (tool flower "What each of the seven areas holds now, as the phone's hub shows it: its live Claude sessions, open luvus tasks, the windows on its niri workspace and its knowledge-base notes, six at a time. Returns JSON." {} $read_only)
  ]
}

# The command line each tool runs.
def command-for [name: string, arguments: record] {
  match $name {
    census => [census --json]
    prune => (if ($arguments.yes? | default false) { [prune --yes] } else { [prune] })
    sessions => [sessions --json]
    sidebar => [sidebar]
    flower => [flower]
    _ => null
  }
}

def call-tool [params: record, start: string] {
  let name = ($params.name? | default "")
  let arguments = ($params.arguments? | default {})
  let args = (command-for $name $arguments)
  if $args == null { return { error: { code: -32602, message: $"unknown tool: ($name)" } } }
  let script = ($env.HONEYCOMB_SCRIPT? | default "")
  if $script == "" { return { error: { code: -32603, message: "HONEYCOMB_SCRIPT is not set" } } }
  let where = ($arguments.directory? | default $start | path expand)
  if not ($where | path exists) {
    return { result: { content: [{ type: text, text: $"no such directory: ($where)" }], isError: true } }
  }
  let run = (do { cd $where; ^$nu.current-exe --no-config-file $script ...$args | complete })
  let text = if $run.exit_code == 0 { $run.stdout | str trim } else { [$run.stdout $run.stderr] | str join "\n" | str trim }
  { result: { content: [{ type: text, text: $text }], isError: ($run.exit_code != 0) } }
}

# The reply to one request, as { result } or { error }, or null for a
# notification, which gets none.
def handle [message: record, start: string] {
  let method = ($message.method? | default "")
  let params = ($message.params? | default {})
  match $method {
    initialize => ({
      result: {
        protocolVersion: ($params.protocolVersion? | default $protocol)
        capabilities: { tools: { listChanged: false } }
        serverInfo: { name: honeycomb, version: "1" }
        instructions: "Honeycomb keeps every collection a person navigates to six members. Call `census` before starting a topic, workspace or worktree; when a count is over six, finish, park or abandon one first."
      }
    })
    ping => ({ result: {} })
    "tools/list" => ({ result: { tools: (tools) } })
    "tools/call" => (call-tool $params $start)
    _ => (if ($method | str starts-with "notifications/") { null } else { { error: { code: -32601, message: $"unknown method: ($method)" } } })
  }
}

def send [reply: record] { print ($reply | to json --raw) }

def main [] {
  let start = $env.PWD
  # Read stdin through `cat`: a script's own $in (`nu --stdin`) arrives only
  # once stdin closes, which a client never does while it waits for replies.
  ^cat | lines | each {|line|
    if ($line | str trim) == "" { return }
    let message = (try { $line | from json } catch { null })
    if ($message | describe | str starts-with "record") == false {
      send { jsonrpc: "2.0", id: null, error: { code: -32700, message: "not a JSON-RPC message" } }
      return
    }
    let reply = (try { handle $message $start } catch {|error| { error: { code: -32603, message: $error.msg } } })
    # A notification (no id) gets no reply, even an error.
    if $reply != null and "id" in ($message | columns) {
      send ({ jsonrpc: "2.0", id: $message.id } | merge $reply)
    }
  } | ignore
}

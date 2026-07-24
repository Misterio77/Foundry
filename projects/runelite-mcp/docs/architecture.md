# Architecture

## Shape

```text
local MCP client
      |
      | Streamable HTTP / JSON-RPC
      v
McpHttpServer -- McpDispatcher -- capability registries
                                      |
                                      v
                           SnapshotProvider interface
                                      |
                            RuneLite client thread
                                      |
                              RuneLite Client
```

The plugin is the MCP server. There is no exporter file, companion daemon, or
remote service between the MCP client and RuneLite.

## Components

- `RuneLiteMcpPlugin`: lifecycle and dependency wiring.
- `RuneLiteMcpConfig`: loopback port and future explicit privacy controls.
- `McpHttpServer`: transport limits, HTTP validation, Origin policy, and worker
  threads. It has no RuneLite API dependency.
- `McpDispatcher`: JSON-RPC and MCP method handling. It has no transport or
  RuneLite API dependency.
- `SnapshotProvider`: narrow boundary used by capabilities, parameterized by a
  focused `SnapshotType` so unrelated domains are not scanned together.
- `RuneLiteSnapshotProvider`: schedules focused reads with `ClientThread`, produces
  immutable JSON snapshots, bounds item output before serialization, and enforces
  a timeout.
- Future registries: typed tools, resources, prompts, and event history.

## Threading

HTTP handlers run on daemon worker threads. They must never directly read the
RuneLite `Client`. `RuneLiteSnapshotProvider` queues a small read on
`ClientThread`, completes a future, and lets the HTTP worker serialize/filter the
result. Blocking I/O must never run on the client thread.

Snapshots are preferred over holding references to RuneLite actors, widgets, or
item containers after leaving the client thread.

## Transport

The first transport is stateless MCP Streamable HTTP:

- fixed endpoint: `http://127.0.0.1:<port>/mcp`;
- POST responses use `application/json`;
- notifications return HTTP 202;
- initialization is the only request that does not require the
  `MCP-Protocol-Version: 2025-11-25` header;
- GET currently returns 405 because the server emits no unsolicited messages;
- no session ID is required;
- request bodies are bounded at 1 MiB;
- browser Origins other than loopback HTTP origins are rejected.

Because the transport is stateless, disabling the plugin does not proactively
remove tools already cached by an MCP client. Calls fail while the listener is
down and recover after it returns; this behavior is verified with Pi. SSE and
sessions should be added only when subscriptions or server-initiated
notifications have a concrete use. Stdio does not fit an in-process GUI plugin
lifecycle.

## Protocol implementation choice

The protocol subset is implemented directly with Gson and JDK `HttpServer`.
RuneLite already supplies Gson, while the official Java MCP SDK would add a large
third-party dependency graph and slow Plugin Hub review. The wire layer stays
small and is covered by fixture and compatibility tests. Revisit this choice if a
small SDK transport becomes part of RuneLite's dependency graph.

The only protocol target is MCP `2025-11-25`. Unsupported protocol versions fail
cleanly; no legacy negotiation or compatibility paths are carried before 1.0.
Likewise, pre-1.0 capability interfaces are replaced outright when a better shape
emerges instead of accumulating aliases and deprecations.

## Capability design

Capabilities are curated and typed. A capability receives validated arguments
and calls domain services; it never receives the RuneLite `Client`, reflection
objects, or an arbitrary class/method name. Plugin registry introspection and
cross-plugin adapters are outside the project scope.

Responses should include:

- semantic names alongside RuneLite numeric IDs where available;
- coordinate system and plane for locations;
- availability/freshness metadata for data that depends on an open UI;
- truncation and total counts for bounded lists;
- game state when absence could otherwise be misinterpreted.

Large datasets use query/filter tools instead of dumping everything into model
context. Capabilities should share one availability vocabulary rather than each
inventing booleans for logged-out, closed-widget, and unavailable states.

## Packaging and deployment

The plugin source remains in `projects/runelite-mcp`; Nix-specific build machinery
lives in `pkgs/runelite-mcp`. The package uses Gradle 8 with Java 11, runs tests,
and installs a dependency-free plugin jar. Home Manager links that jar into
`~/.runelite/sideloaded-plugins/` for the developer-mode RuneLite launcher.

The separation is intentional: the project remains a conventional Plugin Hub
repository, while Foundry owns reproducibility and local deployment. Updating
Gradle or RuneLite dependencies requires regenerating
`pkgs/runelite-mcp/deps.json` and rebuilding the package.

## Failure model

- Protocol/validation failures become JSON-RPC errors.
- Tool failures become MCP tool results with `isError: true`.
- Logged-out or unavailable game data is a successful typed result, not an
  exception.
- Client-thread timeout is bounded and reported without internal paths.
- Listener startup failure prevents plugin startup and leaves no worker threads.
- Shutdown stops accepting requests and terminates workers.

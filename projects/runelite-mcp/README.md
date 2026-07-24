# RuneLite MCP

A local [Model Context Protocol](https://modelcontextprotocol.io/) server running
inside RuneLite. It gives MCP clients current, informational game and client state
without exporting periodic snapshots or controlling the game.

This project is deliberately read-only with respect to gameplay. It does not
click, type, invoke menu actions, send packets, select prayers, or make gameplay
decisions on the player's behalf.

## Status

The foundation milestone is complete. The plugin currently provides:

- MCP `2025-11-25` over Streamable HTTP at
  `http://127.0.0.1:18471/mcp`;
- focused tools for game context, skills, status effects, inventory, and equipment;
- a `runelite://game/context` resource;
- an `osrs_session_brief` prompt;
- live reads marshalled onto RuneLite's client thread;
- loopback-only binding, Origin checks, bounded request bodies, and bounded HTTP
  concurrency;
- clean logged-in/logged-out behavior and disable/re-enable recovery.

Pi consumes the endpoint through the Foundry MCP registry as `osrs`. See the
[requirements](docs/requirements.md), [architecture](docs/architecture.md),
[game-context interface](docs/game-context.md),
[observation tools](docs/observation-tools.md),
[event-history draft](docs/event-history.md), [test strategy](docs/test-strategy.md),
and [roadmap](docs/roadmap.md).

## Installation

Foundry builds the source from this directory as `pkgs.runelite-mcp`. Home Manager
links its jar into `~/.runelite/sideloaded-plugins/`, and the patched RuneLite
launcher enables developer mode so the installed client can load it. Restart
RuneLite after rebuilding, then enable **RuneLite MCP** in its plugin list.

The MCP listener has no authentication. It is intentionally reachable only
through IPv4 loopback and trusts processes running as the local user.

## Development

Enter the Java 11 development shell and run the tests or development client:

```sh
nix-shell
./gradlew check
./gradlew run
```

A valid initialization request:

```sh
curl -s http://127.0.0.1:18471/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"curl","version":"0"}}}' \
  | jq
```

## Plugin Hub posture

The design follows Jagex's third-party client guidelines and RuneLite Plugin Hub
review guidance. Any feature that can cause an in-game action is out of scope, as
are RuneLite plugin introspection and cross-plugin adapters.

The project uses RuneLite's existing Gson dependency and the JDK HTTP server; it
adds no third-party runtime dependencies. Network behavior is explicit and
limited to the configured loopback listener.

## License

[BSD 2-Clause](LICENSE)

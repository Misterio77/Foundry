# RuneLite MCP

A local [Model Context Protocol](https://modelcontextprotocol.io/) server running
inside RuneLite. It gives MCP clients current, informational game and client state
without exporting periodic snapshots or controlling the game.

This project is deliberately read-only with respect to gameplay. It does not
click, type, invoke menu actions, send packets, select prayers, or make gameplay
decisions on the player's behalf.

## Status

Foundation/scaffold. The plugin currently provides:

- MCP over Streamable HTTP at `http://127.0.0.1:18471/mcp`
- `client_state` and `skills` tools
- a `runelite://client/state` resource
- an `osrs_session_brief` prompt
- live reads marshalled onto RuneLite's client thread
- loopback-only binding, Origin checks, and bounded request bodies

See [requirements](docs/requirements.md), [architecture](docs/architecture.md),
[test strategy](docs/test-strategy.md), and the [roadmap](docs/roadmap.md).

## Development

Requires Java 11.

```sh
./gradlew test
./gradlew run
```

Enable **RuneLite MCP** in the development client, then configure an MCP client
with the URL printed in RuneLite's log. No authentication is used: the listener
is intentionally reachable only through IPv4 loopback.

A minimal request:

```sh
curl -s http://127.0.0.1:18471/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | jq
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

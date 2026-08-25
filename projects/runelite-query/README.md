# RuneLite Query

RuneLite Query is a read-only local HTTP API running inside RuneLite. It exposes
current informational game and client state as ordinary JSON without controlling
the game or requiring a companion process.

The plugin does not click, type, invoke menu actions, send packets, select
prayers, or make gameplay decisions. It binds only to IPv4 loopback and has no
authentication; local processes connecting to its port can read the state it
exposes.

## API

The versioned API listens at `http://127.0.0.1:18471/v1` by default. All
operations are `GET` requests and responses use `Cache-Control: no-store`.

```sh
curl -fsS http://127.0.0.1:18471/v1/health | jq
curl -fsS http://127.0.0.1:18471/v1/context | jq
curl -fsS 'http://127.0.0.1:18471/v1/skills?name=Herblore&name=Prayer' | jq
curl -fsS 'http://127.0.0.1:18471/v1/stored-items?container=bank&query=rune&limit=20' | jq
```

The complete route and parameter catalogue is available on demand:

```sh
curl -fsS http://127.0.0.1:18471/v1/openapi.json | jq
```

The API covers session context, skills, effects, carried and observed stored
items, recent events, quests, achievement diaries, combat achievements, Slayer,
Grand Exchange offers, estimated wealth, collection-log summaries, observed POH
features, and RuneLite's cached item prices.

Responses retain explicit game-state, availability, freshness, paging,
partiality, and truncation metadata. Logged-out or unavailable data is a
successful typed response rather than an invented empty value. Invalid requests
return a JSON error object with an appropriate HTTP status.

## Installation

Foundry builds this directory as `pkgs.runelite-query`. Home Manager links the jar
into `~/.runelite/sideloaded-plugins/`, and the patched RuneLite launcher enables
developer mode so the installed client can load it. Restart RuneLite after
rebuilding, then enable **RuneLite Query** in its plugin list.

## Development

Enter the Java 11 development shell and run the tests or development client:

```sh
nix-shell
./gradlew check
./gradlew run
```

Tests use mocked RuneLite snapshot shapes and an actual ephemeral loopback HTTP
server. See [architecture](docs/architecture.md) and [testing](docs/testing.md).

## Plugin Hub posture

The design follows Jagex's third-party client guidelines and RuneLite Plugin Hub
review guidance. Any feature capable of causing an in-game action is out of
scope, as are RuneLite plugin introspection and cross-plugin adapters.

The project uses RuneLite's existing Gson dependency and the JDK HTTP server; it
adds no third-party runtime dependencies.

## License

[BSD 2-Clause](LICENSE)

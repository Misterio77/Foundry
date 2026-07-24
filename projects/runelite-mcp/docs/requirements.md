# Requirements

## Product goal

Expose useful live RuneLite and OSRS context to local MCP clients while remaining
informational, predictable, private to the machine, and acceptable for RuneLite's
Plugin Hub.

## Actors

- **Player:** explicitly installs and enables the plugin.
- **MCP client:** a local agent application connected over loopback HTTP.
- **RuneLite:** owns client state and the client thread.

## Functional requirements

### Protocol

1. Serve MCP Streamable HTTP on a configurable IPv4 loopback port and fixed
   `/mcp` path.
2. Implement JSON-RPC initialization, ping, tools, resources, and prompts.
3. Return structured JSON plus text fallback from tools.
4. Advertise only capabilities that are currently available.
5. Before 1.0, prefer the best tool interface over compatibility: rename or
   replace tools and schemas freely rather than adding aliases, deprecations, or
   legacy code paths. Document breaking changes when releases begin.
6. Return actionable MCP errors without Java stack traces or local paths.

### Information

The target tool families are:

- client/session identity, game state, world, account type, and tick timing;
- player location, movement, animation, interacting entity, and combat status;
- skills, boosts, XP, quests, diaries, combat achievements, and collection log;
- inventory, equipment, bank and other containers, with explicit availability and
  freshness semantics;
- nearby players, NPCs, objects, ground items, projectiles, widgets, and map state;
- active effects such as prayers, boosts, poison, venom, run energy, special
  attack, timers, and Slayer state;
- bounded event history for contextual observations rather than polling races;
- OSRS Wiki search/pages and RuneLite price data where live client data is not the
  authoritative source.

Sensitive information must be opt-in or omitted: chat, friends, clan membership,
private messages, notes, and bank contents are not exposed merely because the
client API can read them.

## Safety and Plugin Hub requirements

1. Bind only to `127.0.0.1`; never wildcard, LAN, or public interfaces.
2. Do not implement game input, menu invocation, packet writing, client scripts,
   automation, prayer/gear switching, or detached-camera interaction.
3. Do not add prohibited boss-mechanic prediction, prayer indicators, automatic
   safe-tile indicators, PvP scouting, or equivalent derived tools.
4. Do not provide a generic `get_var`, `invoke`, reflection, script, or query
   escape hatch. Every exposed operation is reviewed and typed.
5. Make all outbound third-party communication visible in configuration with the
   warning RuneLite requires. Prefer established RuneLite/OSRS Wiki endpoints.
6. Add no runtime dependency unless necessary; Plugin Hub must verify every new
   dependency cryptographically.
7. Bound collection sizes, history, request bodies, and response work.
8. Read RuneLite client state only on the client thread and perform HTTP or other
   blocking I/O off it.
9. Never log private payloads. Errors may identify a tool, not account data.
10. Do not introspect RuneLite's plugin registry or provide cross-plugin adapters.

## Security and privacy

- There is intentionally no application-layer authentication. The trust boundary
  is the local user account and strict IPv4 loopback bind.
- Reject non-local browser origins and non-JSON requests to reduce cross-origin
  abuse from web pages.
- Default-deny sensitive data classes and document every field a tool returns.
- Keep no durable gameplay database. Event history is in-memory, bounded, and
  discarded when the plugin stops.
- Do not expose filesystem paths, environment variables, credentials, session
  tokens, Jagex account identifiers, or unrelated RuneLite configuration.

## Non-functional requirements

- Java 11 and RuneLite Plugin Hub `standard` build compatibility.
- No perceptible client-thread stalls: snapshot collection target under 2 ms;
  expensive transformations happen off-thread.
- A single slow MCP client cannot block RuneLite or other MCP requests.
- Startup/shutdown is idempotent and releases the listener immediately.
- Core protocol and schema logic is testable without launching RuneLite.
- Tool descriptions distinguish current, cached, unavailable, and stale data.

## Acceptance criteria for the first usable release

- Plugin Hub checks and `./gradlew test` pass.
- At least two independent MCP clients initialize and call tools successfully.
- Logged-out, hopping, loading, instanced, and logged-in states return valid data.
- Port conflict and malformed/oversized request failures do not crash RuneLite.
- A manual policy audit finds no path from MCP input to a game action.

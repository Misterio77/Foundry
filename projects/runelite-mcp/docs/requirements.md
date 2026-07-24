# Requirements

This document is normative for the intended product, not an inventory of already
implemented behavior. The README records current capabilities and the roadmap
tracks delivery and exit criteria.

## Product goal

Expose useful live RuneLite and OSRS context to local MCP clients while remaining
informational, predictable, private to the machine, and designed conservatively
for eventual RuneLite Plugin Hub review.

## Actors

- **Player:** explicitly installs and enables the plugin.
- **MCP client:** a local agent application connected over loopback HTTP.
- **RuneLite:** owns client state and the client thread.

## Functional requirements

### Protocol

1. Serve MCP Streamable HTTP on a configurable IPv4 loopback port and fixed
   `/mcp` path.
2. Implement JSON-RPC initialization, ping, tools, and prompts.
3. Return structured JSON plus text fallback from tools.
4. Advertise only capabilities that are currently available.
5. Before 1.0, prefer the best tool interface over compatibility: rename or
   replace tools and schemas freely rather than adding aliases, deprecations, or
   legacy code paths. Document breaking changes when releases begin.
6. Return actionable MCP errors without Java stack traces or local paths.

### Information

The target tool families, in implementation order, are:

- session and player state: game state, world, account type, tick, location,
  movement, animation, interaction target, combat level, and core vitals;
- skills and active effects: levels, XP, boosts, prayers, poison/venom, run
  energy, special attack, timers, and Slayer state;
- carried items: inventory and equipment, with container availability and bounded
  item output;
- bounded event history for state transitions, XP, inventory changes, and only
  explicitly attributable loot or other observations that polling can miss;
- carefully bounded nearby NPC, object, ground-item, widget, and map queries;
- progression and private state: quests, diaries, combat achievements, collection
  log, Grand Exchange, bank, and auxiliary containers;
- OSRS Wiki search/pages and RuneLite price data where live client data is not the
  authoritative source.

Sensitive information must be omitted: chat, friends, clan membership, private
messages, notes, credentials, account identifiers, and nearby player identities.
Gameplay account state—including bank, Grand Exchange, wealth, quests, diaries,
Slayer, achievements, and collection log—is ordinary product data and needs no
privacy gate. A direct player interaction
may expose only that the target is a player and its combat level; names, IDs, and
social relationships remain omitted.

### State semantics

1. Every live-state response identifies the RuneLite game state and sampling tick
   so absence is not mistaken for an empty in-game value.
2. Data whose visibility depends on a widget or container reports a small shared
   availability status such as `current`, `not_logged_in`, or `unavailable`.
3. Cached data is returned only when a capability explicitly promises it and then
   includes its source tick or timestamp.
4. Logout and loading transitions clear current player-bound snapshots rather
   than leaking stale values. Explicitly historical event records may remain
   across transient hops/loading for the same player, but logout or player
   identity change starts a new history generation.
5. Lists report truncation and total counts whenever a configured bound is hit.

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
- Omit social, identity, and credential data; document every field a tool returns.
- Keep no durable gameplay database. Event history is in-memory, bounded, and
  discarded when the plugin stops.
- Do not expose filesystem paths, environment variables, credentials, session
  tokens, Jagex account identifiers, or unrelated RuneLite configuration.

## Non-functional requirements

- Java 11 and RuneLite Plugin Hub `standard` build compatibility.
- Reproducible Nix packaging with a committed Gradle dependency lock.
- No perceptible client-thread stalls: snapshot collection target under 2 ms;
  expensive transformations happen off-thread.
- A single slow MCP client cannot block RuneLite or other MCP requests.
- Startup/shutdown is idempotent and releases the listener immediately.
- Core protocol and schema logic is testable without launching RuneLite.
- Tool descriptions distinguish current, cached, unavailable, and stale data.

## Release acceptance criteria

- Plugin Hub checks, `./gradlew check`, and the Nix package build pass.
- At least two independent MCP clients initialize and call tools successfully.
- Logged-out, hopping, loading, instanced, and logged-in states return valid data.
- Port conflict and malformed, oversized, or concurrent request failures do not
  crash RuneLite.
- Packaged installation, plugin disable/re-enable, and RuneLite restart all
  recover without restarting the MCP client.
- A manual policy audit finds no path from MCP input to a game action.

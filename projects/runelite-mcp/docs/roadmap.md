# Roadmap

## M0 — foundation (complete)

- Plugin Hub-shaped Java project with no additional runtime dependencies.
- Stateless loopback Streamable HTTP transport and MCP `2025-11-25` support.
- Client-thread snapshot boundary, basic tools/prompts, and automated
  protocol/transport tests.
- Reproducible Nix package, Home Manager sideload installation, and patched
  developer-mode RuneLite launch.
- End-to-end Pi verification across logged-in, logged-out, disabled, and
  re-enabled states.
- Requirements, architecture, test strategy, and explicit policy boundary.

## M1 — observational core

### M1a — state and availability (complete)

- A three-sample cold intuition probe informed the documented
  [`get_game_context` interface](game-context.md).
- One shared envelope carries normalized state, exact RuneLite game state, and
  sampling tick.
- Session/player identity, location, movement, animation, interaction target,
  combat level, hitpoints, prayer points, run energy, and special attack are live.
- Provisional interfaces were replaced rather than aliased.
- Automated fixtures cover every RuneLite game state and stale-data transitions.
- Pi verified active play, movement, world-hop `HOPPING`/`LOADING`, transient
  logged-in-without-player, recovery, and logout against the packaged plugin.
- Gradle checks and the reproducible Nix package build pass.

### M1b — skills, effects, and carried items (complete)

- `get_skills` provides case-insensitive filtering with consistent base/current
  levels and XP.
- `get_status_effects` provides signed boosts, active prayers, poison/venom, and
  documented own-character buff timers.
- `get_carried_items` provides inventory and equipment with semantic item names,
  quantities, equipment slots, availability, counts, and hard output bounds.
- Focused snapshot types avoid scanning unrelated domains for every tool call.
- Generic charges are intentionally omitted because RuneLite has no reliable
  item-independent source.
- Pi verified drains, an active protection prayer, inventory/equipment without an
  open widget, container filtering, and packaged-client recovery.
- Gradle checks and the reproducible Nix package build pass.

### M1c — event history (complete)

- `get_events` exposes a 512-record in-memory ring with generation-aware forward,
  backward, filtered, gap-reporting cursor pagination and bounded wire output.
- Typed client-thread reconciliation covers state transitions, skill/XP changes,
  inventory/equipment diffs, movement, and privacy-safe interaction changes.
- Logout/account boundaries clear player-bound history; plugin shutdown discards
  it entirely. Player targets omit identity, and chat/social/bank data is absent.
- Dedicated loot attribution remains deferred rather than mislabelling inventory
  gains or ground spawns.
- Tests cover ring capacity, rollover, reset, cursor/filter/gap behavior,
  concurrency, payload bounds, response trimming, collector reconciliation, and
  player-target privacy.
- Pi verified generation cursors, backward pagination, filtered polling without
  replay, movement, NPC interactions, equipment swaps, item gains/transforms, and
  a correlated 17-XP Fletching change against the packaged plugin.
- Gradle checks and the reproducible Nix package build pass.

### M1d — bounded world context

- Add narrowly scoped NPC, object, ground-item, widget, and map queries only after
  a policy review of each shape.
- Bound distance, result count, fields, and computation before serialization.
- Omit nearby player identities by default and prohibit PvP scouting, boss
  prediction, prayer recommendations, and automatic safe-tile derivation.

## M2 — progression and account state

- Quests, diaries, combat achievements, Slayer, collection log, Grand Exchange,
  bank, wealth, and auxiliary containers are ordinary gameplay data and require no
  privacy gate.
- Social/identity data remains omitted rather than mixed into account-state tools.
- Search/pagination APIs replace context-sized dumps; cached container data carries
  explicit source and freshness metadata.

## M3 — knowledge services

- OSRS Wiki search/page resources and item prices.
- Visible configuration warnings for any third-party requests and their payloads.
- Cache, timeout, rate-limit, and upstream attribution behavior.

## M4 — release hardening

- Full state-transition, performance, privacy, and malformed-input matrix.
- MCP Inspector plus a second independent MCP client compatibility suite.
- Plugin Hub submission metadata, icon, screenshots, and user documentation.
- External review of game-rule compliance and local transport security.

Milestones are capability gates, not promises to expose everything RuneLite can
observe. Anything that makes prohibited gameplay easier in a RuneLite-disallowed
way remains out of scope even if technically read-only.

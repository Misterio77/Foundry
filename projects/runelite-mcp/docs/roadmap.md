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
- Location semantics reuse RuneLite's region catalogue, including template-region
  resolution for instanced content; unmatched areas fail closed to null.
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

## M2 — progression and account state (complete)

- Native tools expose quests, diaries, combat achievements, Slayer, Grand Exchange,
  observed bank/auxiliary containers, rune-pouch contents, wealth estimates, and
  recognized features from the currently loaded player-owned house.
- All gameplay account state is ordinary product data with no privacy gate;
  social/identity data remains omitted.
- Search/pagination APIs replace context-sized dumps. In-memory container caches
  carry source tick/time, survive same-player hops, and clear at account boundaries.
- Collection-log totals and recent entries are available as an explicit summary;
  detailed entries fail closed because RuneLite has no stable complete native model.
- POH ownership is accepted only from direct owner controls or bounded self-entry
  actions (spell, unredirected tablet, or portal Home). Confirmed self-house state
  is refreshed from object events and retained in memory across scene changes;
  guest/unknown houses are never retained.
- Runtime mapping checks, closed schemas, page limits, price-age declarations, and
  rate-limited client-thread timing warnings bound failure and cost.
- Pi verified quest filtering/totals, all diaries, Slayer assignment/rewards,
  combat-achievement mappings and paging, GE, six-slot rune pouch, bank capture and
  search across 748 stacks, convergent wealth, item prices, cache freshness,
  instanced POH detection, three ownership signals, automatic self-house retention,
  and honest unloaded/partial states against the packaged plugin.
- Gradle checks and the reproducible Nix package build pass.

## M3 — knowledge services (complete)

- `get_item_prices` exposes bounded RuneLite cached-price estimates without an
  outbound request.
- Optional OSRS Wiki search and bounded plain-text page tools replace duplicate
  resource wrappers and are advertised only when outbound access is enabled.
- RuneLite configuration warns exactly which query/title fields leave the machine;
  no account or gameplay state is attached.
- Fixed upstream, attribution, descriptive User-Agent, timeouts, one-MiB body cap,
  one-request-per-second limit, and a 64-entry ten-minute memory cache bound I/O.
- Pi verified dynamic 15/17-tool discovery, search and page calls through MCP,
  bounded text truncation, source attribution, and repeat-call cache hits; direct
  upstream fixtures confirmed both MediaWiki query templates.
- Gradle checks and the reproducible Nix package build pass.

## Candidate follow-ups

### Small native additions

- Add player weight and special-attack enabled state to focused live context.
- Emit Grand Exchange offer-change events from RuneLite's native event.
- Add priced-stack/metadata progress to wealth output so a warming estimate cannot
  be mistaken for a stable total even when `partial` is overlooked.

### Investigation required

- Evaluate native Hunter Rumour state and boss/activity kill counts without Hiscore
  identity leakage or cross-plugin coupling.
- Evaluate detailed diary tasks and progression events for quests, diaries, combat
  achievements, and Slayer using bounded varbit reconciliation rather than broad
  per-tick scans.
- Evaluate structured Wiki table extraction under the existing outbound disclosure,
  body, timing, and response-size bounds.
- Keep complete Collection Log detail blocked unless RuneLite gains a stable native
  model; recent-only output must remain explicit.

### Deliberate exclusions

- Do not read RuneLite Notes or other private user-authored text.
- Do not introspect Bank Tags, Inventory Setups, combat-session trackers, or other
  plugins. Their state is plugin-private rather than native account data.
- Do not persist gameplay/event history across RuneLite restarts without a separate
  lifecycle, retention, and privacy design.

## M4 — release hardening

- Full state-transition, performance, privacy, and malformed-input matrix.
- MCP Inspector plus a second independent MCP client compatibility suite.
- Plugin Hub submission metadata, icon, screenshots, and user documentation.
- External review of game-rule compliance and local transport security.

Milestones are capability gates, not promises to expose everything RuneLite can
observe. Anything that makes prohibited gameplay easier in a RuneLite-disallowed
way remains out of scope even if technically read-only.

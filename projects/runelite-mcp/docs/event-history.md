# Event history draft

## Goal

Give MCP clients bounded context for changes that polling can miss without
persisting gameplay data, exposing social/private events, or turning observations
into gameplay recommendations.

M1c adds one read-only `get_events` tool backed by an in-memory ring. It does not
add SSE, subscriptions, filesystem storage, or a generic RuneLite event escape
hatch.

## Tool shape

```json
{
  "name": "get_events",
  "arguments": {
    "generation": "5a1d2d44-0b56-4db4-9509-4a958c7ed93a",
    "afterSequence": 1842,
    "types": ["skill_changed", "inventory_changed"],
    "limit": 50
  }
}
```

Arguments:

- `generation` is required whenever a cursor is supplied and must match the
  current history generation;
- `afterSequence` reads forward from a cursor, returning the earliest matching
  records after it;
- `beforeSequence` pages backward, selecting the latest matching records before
  it;
- `afterSequence` is a nonnegative integer, `beforeSequence` is a positive
  integer, and they are mutually exclusive;
- `types` is a unique array from the closed six-type event catalogue, with at
  most six entries;
- `limit` defaults to 50 and is constrained to 1–100.

Runtime validation additionally rejects `generation` without a cursor, null cursor
fields, non-integral numbers, values above `Long.MAX_VALUE`,
empty or duplicate `types`, unknown/case-variant types, duplicate cursors, and
unknown arguments. Omitting `types` means all six types. Protocol fixtures cover
every branch rather than relying only on advertised JSON Schema.

A call without a cursor returns the newest matching window. Every page is ordered
oldest-first so an agent can apply it chronologically:

```json
{
  "state": "active",
  "sample": {"gameState": "LOGGED_IN", "tick": 9123},
  "history": {
    "generation": "5a1d2d44-0b56-4db4-9509-4a958c7ed93a",
    "oldestSequence": 1800,
    "newestSequence": 1907,
    "pageFirstSequence": 1888,
    "pageLastSequence": 1906,
    "pollAfterSequence": 1907,
    "hasOlder": true,
    "hasNewer": false,
    "gap": false,
    "sizeLimited": false,
    "droppedEvents": 0,
    "events": [
      {
        "sequence": 1888,
        "tick": 9118,
        "type": "skill_changed",
        "data": {
          "skill": "Agility",
          "baseLevel": 58,
          "currentLevel": 58,
          "levelDelta": 0,
          "experience": 238246,
          "experienceDelta": 81
        }
      }
    ]
  }
}
```

`generation` is a random history-lifetime identifier, not an account or session
identifier. It changes when the plugin starts or player-bound history is cleared.
A mismatched cursor generation is an invalid-argument tool error instructing the
client to query again without a cursor; stale numeric cursors are never silently
applied to a new ring.

Cursor rules:

- `pageFirstSequence` and `pageLastSequence` are the first and last returned
  global sequences, or null for an empty page;
- pass `pageFirstSequence` as `beforeSequence` to continue toward older records;
- pass `pageLastSequence` as `afterSequence` to continue toward newer records
  when `hasNewer` is true;
- `pollAfterSequence` is always the query's captured global `newestSequence`,
  including nonmatching records. For a forward query it is safe to adopt only
  after `hasNewer` and `sizeLimited` are both false; otherwise continue from
  `pageLastSequence`. A cursorless latest-window query deliberately uses it to
  start live polling now, leaving any `hasOlder` history for optional backward
  browsing;
- `hasOlder`/`hasNewer` refer only to matching retained records before/after the
  returned page at the query's linearization point.

Gap and range rules are exact:

- `afterSequence < oldestSequence - 1` sets `gap: true` and resumes from the
  oldest retained matching record; equality is not a gap;
- `beforeSequence < oldestSequence` sets `gap: true` and returns no events because
  the requested older range is gone; equality returns an ordinary empty page;
- cursors greater than `newestSequence` are invalid arguments;
- on any gap, bounds and `pollAfterSequence` still describe the current ring;
  clients either consume the retained forward page or restart cursorless;
- an empty ring reports null bounds/page sequences, `pollAfterSequence: 0`, false
  directional/gap flags, and rejects a positive cursor as beyond the current ring.

The query takes one synchronized snapshot of generation, state/sample metadata,
sequence bounds, matching immutable record references, cursors, and gap flags.
Concurrent appends or resets happen entirely before or after that linearization
point; one response never combines metadata from different ring states.

## Retention and lifecycle

- Fixed initial ring capacity: 512 immutable records.
- Sequence numbers are positive signed 64-bit integers starting at one. Before an
  append would exceed `Long.MAX_VALUE`, the ring resets to a new generation and
  the pending record becomes sequence one.
- Overwriting the oldest record is expected and observable through `gap`.
- The ring and all baselines exist only in memory and disappear when the plugin
  stops.
- The first entry into either `LOGIN_SCREEN` or
  `LOGIN_SCREEN_AUTHENTICATOR` starts one contiguous logged-out boundary: it
  clears player-bound history and starts a new generation before recording the
  transition. Duplicate callbacks and movement between the two login-screen
  states update metadata/events without another reset. The boundary flag clears
  only after entering a non-login-screen state, so a later return starts a new
  reset. This safety rule takes precedence even if the sequence began as a hop or
  connection loss.
- `HOPPING`, `CONNECTION_LOST`, `LOADING`, and `LOGGING_IN` retain history while
  invalidating all player-domain baselines. Recovery establishes fresh baselines
  without manufacturing changes. If any sequence subsequently reaches a login
  screen, the preceding reset rule applies.
- If the active local-player name changes without the expected login-screen
  sequence, history is reset before any event for the new player is recorded.
- Plugin disable/re-enable creates a new generation through explicit lifecycle
  teardown, regardless of Guice object reuse.

`LOGGED_IN` alone is not readiness. On each `GameTick`, state is `active` only when
a local player exists. Skill, inventory, equipment, movement, and interaction
baselines initialize independently when their authoritative client data becomes
available. Null item containers remain unavailable and are retried on later ticks;
no event is emitted for a domain until its baseline exists.

## Event catalogue

The catalogue is closed and typed. Adding a RuneLite event requires an explicit
schema, privacy review, bounds, and tests.

### `game_state_changed`

```json
{
  "previous": "LOGGED_IN",
  "current": "HOPPING",
  "state": "loading"
}
```

RuneLite's synchronous client-thread `GameStateChanged` delivery is the safety
boundary for transient logout detection while the plugin is enabled. The handler
reads `Client#getGameState`; if it differs from the callback payload, the payload
is stale/out-of-order and is ignored in favor of the current authoritative value.
Startup sampling and every `GameTick` also reconcile that authoritative value.
A login-screen callback therefore cannot be lost merely because no game tick
occurred during the screen. If the plugin was disabled during the transition,
explicit re-enable lifecycle reset supplies the boundary. This design does not
claim to detect a hypothetical state interval omitted by both RuneLite callbacks
and every client read; RuneLite provides no privacy-safe account identifier that
could reconstruct it.

Login-screen clearing happens before the new transition is inserted. The shared
envelope uses the same mapping as `get_game_context`: `LOGGED_IN` without a local player is `loading`, both login
screens are `logged_out`, and other transitional states are `loading`.

### `skill_changed`

```json
{
  "skill": "Prayer",
  "baseLevel": 50,
  "currentLevel": 42,
  "levelDelta": -8,
  "experience": 107489,
  "experienceDelta": 0
}
```

`StatChanged` marks a skill dirty. The next game-tick reconciliation reads its
authoritative current values and compares them with the baseline. Multiple
callbacks, or a mutation and revert, produce at most one net record for that skill
per tick. A bounded full reconciliation every ten ticks repairs a missed callback.

### `inventory_changed` and `equipment_changed`

```json
{
  "changes": [
    {
      "slot": 3,
      "slotName": "weapon",
      "before": null,
      "after": {"id": 11889, "name": "Zamorakian hasta", "quantity": 1}
    }
  ],
  "truncated": false
}
```

`ItemContainerChanged` marks only local inventory ID 93 or equipment ID 94 dirty.
The next game-tick reconciliation compares bounded slot snapshots, coalescing all
same-tick mutations to one net event per container. A full reconciliation every
ten ticks repairs a missed callback. A mutation reverted before reconciliation
correctly produces no net change.

Inventory changes are bounded to 28 slots and equipment to 14. Equipment entries
include `slotName`. Item IDs and quantities are copied first. A collector-local
256-entry access-ordered LRU caches immutable ID/name pairs and null sentinels for
failed lookups; eldest entries evict deterministically, and the cache clears on
lifecycle or player boundary. At most eight uncached IDs call
`Client#getItemDefinition` in one tick. Before each miss, the collector checks a
1 ms reconciliation lookup budget; once consumed, remaining names stay null. A
throwing lookup is caught, negatively cached, and never aborts the event batch; a
single unexpectedly slow call may exceed the budget but prevents all subsequent
lookups that tick and is covered by the rate-limited timing warning. Additional
misses leave nullable names without lookup. Resolved names are truncated to 64
characters.
No item prices or plugin state are consulted, and normal/worst-case timing tests
include all cache-miss work.

A dedicated `loot` event is deliberately deferred. RuneLite ground-item spawns do
not reliably establish ownership, and inventory gains do not reliably establish a
cause. Consumers may observe an item increase without the server mislabelling it
as loot.

Skill/container history promises net observations at reconciliation boundaries,
not a lossless replay of every server/client mutation. A change reverted entirely
between two game ticks is intentionally invisible. A persistent change is caught
by its dirty callback or, after a missed callback, by the next ten-tick full
reconciliation. Dirty state discarded by hop/logout invalidation is also intentional: retaining
it could manufacture a cross-boundary event. These cases have explicit
deterministic tests.

Within one tick, sequence order is fixed: synthesized state transition first,
skill records in RuneLite skill-enum order, inventory, equipment, movement, then
interaction. Item changes are slot-ascending. Rejected oversized records do not
disturb the relative order of accepted records.

### `movement_changed`

```json
{
  "from": {"x": 3161, "y": 3493, "plane": 0, "regionId": 12598},
  "to": {"x": 3163, "y": 3493, "plane": 0, "regionId": 12598},
  "moving": true,
  "animationId": -1
}
```

Sampled authoritatively once per `GameTick` and emitted only when world location,
moving state, or primary animation changes. At most one movement record is
emitted per tick. Equality compares all four location fields plus `moving` and
`animationId`; equal nullable samples emit nothing. This keeps the ring useful
during sustained travel rather than filling it with client frames.

### `interaction_changed`

```json
{
  "before": null,
  "after": {"type": "npc", "id": 2873, "name": "Gull", "combatLevel": 0}
}
```

Sampled once per game tick using the same target schema and privacy rule as
`get_game_context`: NPC identity is allowed; player names and IDs are omitted.
Target equality uses null/type and NPC ID only. NPC name/combat-level changes do
not imply a new interaction. All player targets intentionally share the same
privacy-safe identity, so switching directly between two players emits no target
change; null↔player still does. Unknown actors compare by type. Changes are
emitted only when this privacy-safe identity changes.

## Payload rules

Fields shown in catalogue examples are required unless explicitly nullable:

- every record requires positive `sequence`, nonnegative `tick`, closed `type`,
  and a type-specific `data` object;
- `skill_changed` always includes signed `levelDelta` and `experienceDelta`, even
  when either is zero;
- item changes require `slot` plus nullable `before`/`after`; at least one side is
  nonnull, and item values require positive `id`, positive `quantity`, and a
  nullable semantic `name` when definition lookup fails;
- equipment changes additionally require `slotName` on the change itself;
- locations require integer `x`, `y`, `plane`, and `regionId`; movement `from` is
  nullable only for the first ready sample;
- interaction targets are null or one of: NPC (`type`, `id`, nullable `name`,
  `combatLevel`), player (`type`, `combatLevel` only), or unknown actor (`type`
  only);
- dynamic names are truncated to 64 characters before entering a record; no
  arbitrary map or extension fields are accepted.

## Collection architecture

```text
RuneLite EventBus callbacks (client thread)
        | mark bounded domains dirty
        v
GameTick reconciliation (client thread)
        | copy reviewed primitives, update baselines, coalesce
        v
EventHistory.append(EventRecord)
        | short synchronized critical section
        v
fixed ring of immutable records
        | atomically select immutable references and metadata
        v
filter result serialization (HTTP worker)
        v
get_events MCP tool
```

`EventHistory` is a pure Java service with no RuneLite dependency.
`RuneLiteEventCollector` owns readiness, dirty flags, baselines, and coalescing on
the client thread. It uses three synchronized history transactions:

- `updateState(metadata)` changes only the shared envelope;
- `appendBatch(metadata, records)` updates metadata and appends one tick's records
  atomically;
- `resetAndAppend(metadata, transition)` replaces generation/ring/sequence and
  inserts the boundary transition atomically.

On a logout or detected player-identity boundary, the collector first increments
its local epoch and clears every baseline/dirty flag, then calls
`resetAndAppend`. Dirty marks carry that epoch and reconciliation discards any
mark not belonging to the current active epoch. RuneLite callbacks are serialized
on the client thread; a query therefore observes either the complete old
transaction or complete new one, never mixed-generation metadata and records.

`RuneLiteMcpPlugin.startUp` constructs a fresh `EventHistory`, calls
`collector.start(history)` to reset all collector state, and schedules an initial
client-thread read of exact game state, tick, local-player readiness, and available
baselines before starting the HTTP server. This does not depend on receiving a
future `GameStateChanged` callback; until the read completes, history remains the
defined `UNKNOWN`/loading empty state. Shutdown closes the server first, calls
`collector.stop()` to increment the epoch and drop baselines/dirty flags/history
references, explicitly clears/closes the history, and nulls both references.
Tests reuse one collector across two start/stop cycles and prove that no record,
cursor, generation, or pending dirty mark survives.

Client-thread work is bounded by 24 skills, 28 inventory slots, 14 equipment
slots, eight uncached item definitions, and one movement/interaction sample.
Handlers perform no JSON serialization, item-price lookup, network access, or
unbounded work. Reconciliation measures its complete client-thread duration and
emits a payload-free warning at most once per minute if one pass exceeds 5 ms.

The history service tracks the latest normalized state, exact game state, local
player readiness, and tick. `get_events` therefore returns the shared envelope
without scheduling a second client-thread snapshot that could race the selected
records.

Records and payloads are deep immutable typed Java values: final scalar fields and
unmodifiable defensive copies of typed lists/objects, never retained Gson trees or
caller-owned maps. JSON trees are created only by the HTTP worker. Mutation and
concurrent-serialization tests retain and alter every constructor input after
append and prove ring output cannot change.

`EventRecordFactory` sanitizes each typed payload, makes defensive copies, and
computes a conservative maximum encoded size before append: fixed JSON syntax and
numeric maxima plus six output bytes per retained UTF-16 character (the worst JSON
escape). It rejects anything above 16 KiB. `appendBatch` skips each rejected record
independently, increments `droppedEvents` once per rejection, and assigns sequences
to accepted records only; other records in the batch remain ordered and valid.
Dynamic strings are limited to 64 characters, item-change arrays to their
container capacity, and event types to the closed six-value enum.

The HTTP worker builds a candidate MCP result and serializes the complete JSON-RPC
response including structured content and text fallback. If its UTF-8 wire body
exceeds 512 KiB, a binary search selects the largest fitting event count (the
forward-page prefix or latest/backward-page suffix), requiring at most eight
additional encodes for the 100-record maximum. It then recomputes page
cursors/directional flags and sets `sizeLimited`. After trimming,
`hasOlder`/`hasNewer` are evaluated against all matching retained records outside
the final page, `gap` remains a property of the input cursor, and
`pollAfterSequence` remains the query's linearized watermark. Rejections produce a
rate-limited payload-free warning. Exact tests cover single and multiple rejected
records in mixed batches, sequence/counter behavior, filtered forward prefixes,
filtered backward suffixes, multibyte UTF-8 names, and bodies exactly below/above
512 KiB including both MCP representations.

## Privacy and policy boundary

Never record:

- chat, private messages, overhead text, friends, clan, notes, or notifications;
- account hashes, Jagex account identifiers, session tokens, or filesystem data;
- nearby player identity or player interaction identity;
- menu entries, clicks, keys, packets, scripts, inferred intent, recommended
  prayers, safe tiles, boss predictions, or PvP scouting data;
- bank or auxiliary-container changes before their separately gated privacy work.

History is observational evidence, not an automation queue. No sequence or event
may be accepted back as input to invoke a game action.

## Failure and availability semantics

- Before the startup client-thread read or first state callback completes, return
  `state: "loading"`, exact state `UNKNOWN`, tick zero, and empty history.
- During hops/loading/disconnects, return `state: "loading"` and the latest exact
  state/tick while retaining pre-transition history but no valid baselines.
- Logged-out history contains only post-clear lifecycle events.
- Unknown/duplicate event types, conflicting cursors, missing/mismatched cursor
  generations, negative cursors, and limits outside the schema produce actionable
  invalid-argument errors.
- Ring reads remain available while RuneLite is logged out; the plugin listener
  itself being unavailable remains an HTTP/MCP connection failure.

## Test plan

### Pure ring

- empty, partial, full, and overwritten rings;
- cursorless latest window, backward pages, forward polling, and type filters;
- generation mismatch, reset, gap, and sequence rollover boundaries;
- one linearization point under concurrent append/query/reset and deep
  immutability under mutation/concurrent serialization;
- no duplicate or skipped retained records when draining a byte-limited forward
  page before adopting `pollAfterSequence`;
- filtered backward trimming, count/byte limits, oversized-record accounting,
  multibyte UTF-8, and worst-case record/wire bounds.

### RuneLite adapter

Tests use a mutable fake `ObservationSource` plus direct, ordered calls to
`onGameStateChanged`, `onStatChanged`, `onItemContainerChanged`, and `onGameTick`.
Each fixture states the source values before every callback, the collector epoch,
the tick assigned to flushed records, and the exact resulting batch. Required
sequences include callback-before-tick, callback-after-previous-tick, duplicate
callback, mutation/revert, forced ten-tick reconciliation, and a dirty callback
followed by hop/logout invalidation before reconciliation.

- enable-while-logged-in, enable-during-loading, and no subsequent state callback;
- delayed local-player and container readiness after `LOGGED_IN`;
- duplicate, out-of-order, missed, rapid, and mutation/revert callbacks;
- independent baseline initialization, ten-tick reconciliation, fixed intra-tick
  ordering, and rejected-record ordering;
- exact sequences `LOGGED_IN→HOPPING→LOADING→LOGGED_IN`,
  `LOGGED_IN→CONNECTION_LOST→LOGGING_IN→LOGGED_IN`, and disconnect/hop sequences
  that end at either login-screen state;
- duplicate/oscillating login-screen states, unexpected player-identity change,
  disable/re-enable with collector reuse, and shutdown resets;
- throwing, negatively cached, and deliberately slow item-definition lookups with
  lookup-budget and warning assertions;
- explicit negative fixtures proving player targets omit identity, social/chat
  events have no adapter, and bank/auxiliary container IDs are ignored.

### Protocol and live verification

- exact fixture for every event and state envelope;
- all valid/invalid argument combinations and MCP text fallback;
- Pi polling across XP gain, item/equipment changes, movement, NPC and player
  interaction, hop, logout, plugin restart, and ring overflow;
- cursor-following calls recover missed changes without duplicates;
- client-thread timing is measured over at least 10,000 passes separately for
  normal dirty-domain ticks and forced worst-case reconciliation. Both include
  source reads, eight cold name lookups, baseline copies, event construction, and
  ring append; each must remain below 2 ms p95 with no pass above the 5 ms
  rate-limited-warning threshold.

## Implementation slices

1. **Pure ring:** immutable `EventRecord`, generation/reset behavior, bounded
   overwrite, bidirectional pagination, linearizable metadata, and cursor tests.
2. **Lifecycle and skills:** state/readiness tracking, baseline resets,
   `StatChanged` reconciliation, and initial `get_events` protocol fixtures.
3. **Containers:** inventory/equipment dirty tracking, bounded reconciliation,
   semantic item copies, and privacy-negative tests.
4. **Movement and interaction:** game-tick sampling, target privacy, and world-hop
   behavior.
5. **Live verification:** execute the protocol/live matrix, performance check, and
   policy audit before marking M1c complete.

## Exit criteria

- Gradle checks and the reproducible Nix package build pass.
- Pure tests cover every cursor, overwrite, reset, concurrency, and bound rule.
- Every event payload has an exact fixture and privacy-negative counterpart.
- Login/logout/hop/readiness tests prove baselines cannot leak or manufacture
  changes.
- Live Pi calls recover missed changes without duplicates when following returned
  cursors.
- A policy audit confirms the event catalogue contains no social/private data,
  gameplay actions, or prohibited derived guidance.

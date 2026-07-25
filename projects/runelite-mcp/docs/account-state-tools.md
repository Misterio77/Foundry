# Progression and account-state tools

M2 exposes gameplay account state as ordinary read-only product data. It does not
privacy-gate bank value, progression, or Grand Exchange activity. Social data,
credentials, Jagex account identifiers, and nearby-player identity remain omitted.
All responses use the shared `state` and `sample` envelope.

## `get_quests`

Returns quest-point and state totals plus a page of `{id, name, state}` entries.
`states`, case-insensitive `query`, `offset`, and `limit` (maximum 100) filter the
page. States are `not_started`, `in_progress`, `finished`, and `unknown`.

## `get_achievement_diaries`

Returns all twelve regions and their easy, medium, hard, and elite reward-tier
states. Optional `regions` selects named region keys. Completion means the tier's
reward varbit is nonzero; `rewardValue` is retained because some rewards have more
than one claimed state.

## `get_combat_achievements`

Returns overall and per-tier totals plus a bounded task page. `tiers`, `completed`,
`query`, `offset`, and `limit` filter tasks. Static task definitions come from the
current game cache's tier enums and structs; `definitionsAvailable: false` fails
closed if those mappings stop resolving.

## `get_slayer`

Returns the current assignment, points and streaks, reward unlocks, extensions,
auto-kill toggles, and per-master block lists. Optional `sections` selects `task`,
`rewards`, or `blocks`. Task, area, and boss names use RuneLite's native game DB
and are nullable when definitions are not loaded.

## `get_grand_exchange`

Returns the eight native offer slots, omitting empty slots. Quantities, listed
prices, and spent GP are authoritative client values. Market and account values
are estimates from RuneLite's price cache and declare `priceSource` plus the
maximum five-minute in-plugin price age.

## `get_stored_items`

Searches `bank`, `seed_vault`, `looting_bag`, `rune_pouch`, `seed_box`,
`tackle_box`, `forestry_kit`, and `huntsmans_kit`. At most four containers and 100
matching stacks are returned per call; `query`, `itemId`, `offset`, and `limit`
provide bounded paging.

Bank and auxiliary containers are retained in memory only after RuneLite emits a
container update. They report `observed` with `observedTick` and `observedAt`, become `stale` after
one hour, or report `unavailable`; an unloaded container is never presented as
empty or current.
Caches survive transient loading/world hops for the same player, clear at login
screens, direct player-identity changes, plugin shutdown, and RuneLite restart.
Rune-pouch slots come from current named varbits and are copied into the same
account-generation cache before worker-side serialization.

## `get_account_wealth`

Returns a known-total estimate and separately labelled bank, carried-item,
auxiliary-container, rune-pouch, and GE components. `partial` remains true while
any component or item metadata is unavailable. Item names/prices are enriched in
batches of eight per client tick; `metadataComplete` makes convergence explicit
instead of stalling RuneLite on a large bank. This is an estimate, not an
authoritative account valuation.

## `get_collection_log`

Returns native totals by top-level category when RuneLite has loaded them and up
to twelve recent item IDs/names. `recent_only` plus `synchronization: unknown`
prevents unloaded zero totals from looking authoritative. RuneLite has no stable
complete account-level collection-log entry
model; the tool therefore declares `completeness: summary`, exposes the recent
item date encoding only as `dateValueRaw`, and marks detailed entries unavailable
rather than scraping transient widgets or coupling to another plugin.

## Bounds and lifecycle

Arguments are closed schemas. Query text is limited to 128 characters, arrays are
unique and enum-bounded, offsets are nonnegative signed integers, and page limits
are 1–100. Raw client state and at most eight queued item definitions/prices are copied on
RuneLite's client thread with a two-second outer timeout. Container paging,
valuation, and JSON construction run on the HTTP worker; progression reads over
5 ms generate a rate-limited payload-free warning. Account generations are checked
before and after worker serialization so logout/account changes cannot publish a
mixed response. No account-state data is written to disk by this plugin.

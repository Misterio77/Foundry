# Architecture

```text
curl or another local HTTP client
              |
              | GET /v1/...
              v
      QueryHttpServer -- QueryDispatcher -- SnapshotProvider
              |                 |                  |
              |                 v                  v
              |            EventHistory     RuneLite client thread
              |                                    |
              +-------------------------------- RuneLite Client
```

The plugin is the API server. There is no exporter, companion daemon, periodic
snapshot file, or remote service between the caller and RuneLite.

`QueryHttpServer` owns loopback HTTP concerns: routing, query decoding, Origin
policy, bounded query strings, worker concurrency, JSON errors, and static
OpenAPI discovery. `QueryDispatcher` validates domain arguments, filters focused
snapshots, and queries bounded event history. It has no HTTP dependency.

HTTP workers never read the RuneLite client directly. Snapshot requests marshal a
small focused read onto RuneLite's client thread, copy scalar state into JSON or
immutable caches, and perform paging and valuation back on the worker. Calls have
a bounded timeout. Event queries copy immutable records and coherent cursor
metadata under the history lock before filtering and serialization.

The API is deliberately fixed and typed. It does not expose arbitrary RuneLite
classes, reflection, plugin registries, or generic URLs. Responses use semantic
names where available and explicitly report game state, data availability,
freshness, paging, partial results, and truncation.

The listener binds to `127.0.0.1`, rejects non-loopback browser Origins, emits
`Cache-Control: no-store`, and accepts only read-only `GET` requests. It trusts
other processes running as the local user. Request concurrency, query length,
list sizes, event retention, and event response serialization are bounded.

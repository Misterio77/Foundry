# Testing

The test suite separates RuneLite reads, domain dispatch, and HTTP behavior.

- Snapshot-reader tests mock RuneLite client interfaces and verify active,
  transitional, unavailable, cached, and bounded response shapes.
- `QueryDispatcherTest` feeds representative mocked snapshot shapes through every
  domain operation, verifies direct JSON output and typed filtering, and exercises
  generation-aware and response-size-bounded event history.
- `QueryHttpServerTest` starts a real server on an ephemeral loopback port, calls
  every documented route, verifies query-parameter translation, validates the
  served OpenAPI document, and checks HTTP, Origin, and structured-error behavior.
- Event and account-cache tests cover retention, account boundaries, coalescing,
  paging, valuation, and stale-data semantics independently of HTTP.

Run all checks with:

```sh
nix-shell --run './gradlew check'
```

For a live structural comparison during protocol changes, query the installed
plugin and compare JSON path/type sets rather than committing account values.
No live account snapshots belong in fixtures or the repository.

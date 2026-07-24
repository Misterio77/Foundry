# Test strategy

## Test layers

### Pure unit tests

Run without RuneLite or sockets:

- JSON-RPC request validation, IDs, errors, and notifications;
- initialization and capability negotiation;
- tool argument validation and output schemas;
- filtering, pagination, truncation, freshness, and coordinate conversion;
- privacy defaults and prohibited-operation deny lists;
- event-ring ordering and capacity.

Use a fake `SnapshotProvider`; do not mock the broad RuneLite `Client` API in
protocol tests.

### Transport integration tests

Start `McpHttpServer` on loopback with an ephemeral port and use JDK `HttpClient`:

- initialize, ping, list, call, resource read, and prompt get;
- content types, HTTP methods, notifications, malformed JSON, and unknown methods;
- non-loopback Origin rejection;
- 1 MiB body limit and concurrent requests;
- stop/restart and port-conflict behavior.

### RuneLite API contract tests

Compile against `latest.release` on every change. Focused tests cover snapshot
mapping with RuneLite test fixtures where feasible. The development client smoke
suite covers APIs that require a live client.

### MCP client compatibility

Before release, run the same black-box suite against at least:

- Pi's MCP client;
- MCP Inspector;
- one other independent Streamable HTTP client.

Capture protocol fixtures for initialization, tools, resources, prompts, errors,
and notification responses. Fixtures contain synthetic account data only.

### Manual safety and gameplay-state matrix

Test with a disposable/non-sensitive profile across:

- startup logged out, login, logout, world hop, connection loss;
- normal world, instance, underground map, and loading transitions;
- bank/widget closed versus open, empty containers, and full containers;
- plugin disable/re-enable and RuneLite shutdown.

## Policy regression tests

A source-level test/check should reject imports or calls associated with:

- menu invocation and menu-entry injection;
- mouse/keyboard input synthesis;
- packet or client-script execution;
- reflection and dynamic class loading;
- non-loopback listener addresses.

This is defense in depth, not proof of policy compliance. Each release still gets
a human diff audit against the current Jagex guidelines, RuneLite Plugin Hub
review page, and rejected/rolled-back feature list.

## Performance tests

- Measure client-thread snapshot time independently of JSON serialization.
- Exercise worst-case nearby entities and container sizes.
- Assert list limits before serialization.
- Soak concurrent polling while watching client tick and frame timings.

Targets: p95 client-thread collection below 2 ms, no unbounded queues, and no
request worker surviving plugin shutdown.

## CI gates

```sh
./gradlew test
./gradlew check
```

Release candidates additionally run Plugin Hub tooling/checks, MCP compatibility,
live-client smoke tests, and the policy audit. Coverage percentage is advisory;
behavioral boundary coverage is the gate.

# Scoring

Map each decision to exactly one bucket. When between buckets, choose the one implying the larger interface change; hindsight must not rationalize a divergence into a match.

| Bucket | Meaning | Default move |
|---|---|---|
| `match` | Reality has the expected name and shape | Keep it |
| `naming-mismatch` | Correct concept/shape, different name | Rename or add the expected alias |
| `shape-mismatch` | Different structure, arguments, return, placement, or idiom | Reshape toward the familiar expectation |
| `missing-affordance` | The expected capability does not exist | Build it |
| `hallucinated` | A confidently invented call/key/interaction does not exist | Treat the invention as a candidate spec and build it |

Use the probe's pre-reality confidence as the base signal. A named, widely familiar anchor strengthens the result. With multiple probes, convergence matters more than any one confidence label. Mark priority only when at least two probes independently converge.

Conforming is the default, not a law. Keep the unfamiliar design and teach it in docs only when conforming would be unsafe, violate a hard invariant, or impose unacceptable compatibility cost; name the constraint explicitly and consider rerunning a doc-informed probe after changing the docs.

Include strong `wished_existed` entries as `missing-affordance` or `hallucinated` findings. Do not count matches as divergences.

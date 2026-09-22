# todomd design

This document records the implemented model and its invariants. User-facing
configuration and syntax belong in [README.md](README.md); future work belongs
in [ROADMAP.md](ROADMAP.md).

## Model

`todomd` is a transactional Markdown editor over vdir VTODO files:

```text
ICS files ──▶ repository state ──▶ view projection ──▶ Markdown
    ▲                                                    │
    └──────────── validate, reconcile, plan, apply ◀─────┘
```

The repository state is semantic and deterministic. A resolved view controls
only grouping and ordering during projection. Parsed Markdown is compared with
the rendered baseline and freshly loaded ICS state before any write.

A **task tree** is a root followed by all descendants. A **view** contains an
ordered sequence of grouping keys and an ordered sequence of sorting keys. A
**group** is the tuple of root values selected by those grouping keys.

## Invariants

1. ICS is the source of truth; Markdown is a private, session-scoped editing
   surface.
2. Identity markers, not position or summary text, identify existing tasks.
3. Explicit task fields override grouping headings. Headings supply only fields
   omitted from roots.
4. Descendants inherit their root's list; parent and child can never cross list
   boundaries.
5. A tree is indivisible for top-level grouping and ordering. Descendant fields
   do not select groups.
6. Ordering alone is presentational. It never enters a change plan.
7. View changes on a clean document do not write ICS or run hooks.
8. Equal repository state and an equal view produce byte-identical Markdown.
9. Writes preserve source data outside the planned semantic change.

## Repository state

Each selected list has a stable display name and an ordered set of parsed
VTODOs. A semantic task contains its UID, summary, completion state, parent,
priority bucket, sorted categories, and optional start and due values. A
separate source snapshot maps lists and tasks to source files and hashes.
Parsed task order retains the read-only manual ranking used for projection and
source-side change detection.

The reader discovers collections, validates list identity, parses one primary
VTODO per file, resolves parent relationships, and builds a forest. Empty or
dangling relationships render as roots. Cycles are rejected. Tasks without a
summary, and their descendant subtrees, are unrepresentable and reported rather
than exposed as destructive Markdown omissions.

Repository loading does not apply a view. Its sequence remains useful for the
read-only `manual` sorting key and for detecting source-side order changes.

## Views

### Resolution

Resolution precedence is:

1. explicit `--group-by`, `--no-group`, or `--sort-by` fields;
2. `--view NAME`;
3. configured `default_view`; and
4. the built-in default.

The resolved `View`, not merely its name, is stored in live metadata so an open
session remains reproducible after configuration changes.

Validation rejects unknown keys, duplicate keys, unknown view names, and an
empty sorting sequence. Grouping may be empty.

### Projection

Grouping keys are `list`, `completed`, `priority`, `due`, `start`, and
`categories`. They are evaluated on roots from left to right. The resulting
tuple orders groups before `sort_by` is considered.

Natural group order is:

| Key | Order |
|---|---|
| `list` | selected-list order |
| `completed` | incomplete, completed |
| `priority` | high, medium, low, none |
| `due`, `start` | ascending, missing last |
| `categories` | complete sorted set, empty last |

Category sets form one group value; projection never duplicates a task into
several groups. Missing fields receive explicit labels such as `No due date`.

Sorting keys are `list`, `completed`, `manual`, `due`, `start`, `priority`, and
`summary`. Sorting is view-wide. Every sibling set is sorted recursively, every
parent remains before its descendants, and task identity is the final stable
tie-breaker.

Dates sort by local calendar date. On one date, specific times sort
chronologically before the all-day value. Missing dates sort last. List sorting
uses selected-list order; priority is high to none; summaries compare
case-insensitively.

The default view groups by list and sorts by completion, priority, then summary.

### Nested groups

Heading depth matches grouping-key position. For:

```toml
group_by = ["due", "list", "priority"]
```

```markdown
# 2026-09-22

## Magalu

### High priority

- [ ] Executar CR <!--t1-->
```

The root receives all three omitted fields from its heading path. Moving it to a
different valid heading edits the corresponding field. Trees remain intact even
when descendants carry different due dates, priorities, or categories.

## Markdown

### Grammar

A task line has a checkbox, unordered leading fields, a summary, and an optional
trailing session identity:

```markdown
- [ ] @Postgrad -2026-09-12 +"2026-09-07 09:00" !!! [Research, "Quick Win"] Write paper <!--t1-->
```

Canonical field order is list, due, start, priority, categories, summary, then
identity. Parsing accepts fields in any order.

- `@name` is singular list membership and is legal only on roots.
- `-value` and `+value` are due and start.
- `!`, `!!`, and `!!!` are priority buckets.
- `[a, b]` is the complete category set.
- Two spaces are one hierarchy level.
- `<!--tN-->` at the end is a session identity.

Marker values use doubled-quote escaping. A summary is quoted only when its
start could be parsed as syntax, edge whitespace must survive, or its end looks
like an identity marker. Other HTML comments remain summary text.

The parser rejects malformed tasks, duplicate fields or identities, skipped
indentation levels, duplicate categories, unknown identities, cross-list
parenting, and empty or multiline summaries.

### Heading authority

For each root, authority is:

1. explicit task marker;
2. corresponding grouping heading; then
3. the field's empty/default value where legal.

Active list, due, start, priority, and category groupings omit that root marker
from canonical Markdown. The parser restores it from the heading path. An
explicit conflicting marker wins and causes the task to move to its canonical
group after save.

Completion is different: every task must contain `[ ]` or `[x]`, so the checkbox
always wins over a completion heading. Descendants never inherit heading fields;
they retain their own markers and inherit only list membership from the parent.

Grouping labels are strict parse tokens:

- lists must name selected lists;
- priority and completion labels must match canonical labels;
- dates must parse as date input or use their canonical missing label; and
- categories must use canonical bracket syntax or `No categories`.

A root must have a complete heading path for the active grouping. Headings
deeper than the configured grouping depth are decorative and ignored. Headings
do not reset task indentation.

### Dates

Date-only and datetime values remain distinct. Datetimes are normalized to an
instant and rendered in local time; source UTC or `TZID` values retain their raw
representation when unchanged. Canonical Markdown omits seconds, but equality
logic preserves hidden source precision.

When one side of a start/due pair is a date and the other a datetime, the date is
promoted to local midnight before writing. Changed pairs must satisfy start ≤
due. Fractional seconds are rejected because RFC 5545 DATE-TIME cannot represent
them.

## Reconciliation

Manual `session apply` and LSP saves use the same reconciliation and transaction
engine. Three semantic states participate in each operation:

- **baseline:** what the accepted Markdown was rendered from;
- **Markdown:** the parsed editor buffer; and
- **current ICS:** sources reread immediately before planning.

The result is:

| Markdown changed | ICS changed | Result |
|---|---|---|
| no | no | no change |
| no | yes | inbound refresh |
| yes | no | outgoing plan |
| yes | yes | conflict |

Comparison ignores view order and heading layout after headings have supplied
their semantic root fields. It preserves untouched source details such as exact
priority values, seconds, timezone representation, and unrelated properties.

A plan contains creates, updates, and deletes over semantic tasks. New tasks use
draft references so children can target parents created in the same
transaction. Retained children must remain attached to another retained or new
parent.

## Applying changes

Before writing, todomd verifies selected-list identity, membership, and source
hashes. Each operation is rechecked immediately before execution. Writes use
private temporary files and atomic rename; originals and the serialized plan
are retained in a numbered transaction directory.

If an operation fails, already-applied operations receive a hash-guarded
best-effort rollback. Multi-file updates cannot be truly atomic, so transaction
artifacts remain available for manual recovery after interruption.

Patching changes only exposed fields. It preserves descriptions, alarms,
unrelated `RELATED-TO` forms, extension properties, nested components, and raw
unchanged categories and dates. Parent edits write
`RELATED-TO;RELTYPE=PARENT`. `SEQUENCE` advances for changed existing VTODOs.

## Sessions and LSP

A session stores:

- selected lists, scope, resolved configuration, and active view;
- semantic baseline and identity manifest;
- accepted canonical Markdown;
- recovery state for tasks outside the active rendering scope; and
- numbered transaction artifacts.

The explicit `session create`, `session apply`, and `session close` commands
expose this lifecycle without requiring an editor or LSP. Manual and live modes
use the same creation primitive and accepted-state renderer; their adapters only
differ in whether canonical Markdown replaces `tasks.md` directly or is sent as
an LSP workspace edit. Creation prints the session directory. Apply reconciles
once, atomically advances the accepted artifacts and canonical `tasks.md`, and
always keeps the session reusable. Close refuses byte-dirty Markdown unless
`--force` is given. Apply, close, and an attached language server hold the same
exclusive session lock.

The language server attaches only to recognized private sessions. It validates
while typing and reconciles on save. Successful outgoing changes and inbound ICS
changes return a versioned whole-document workspace edit. Invalid input and
conflicts leave both sources untouched and produce diagnostics.

Selected list directories are watched. Completed tasks from an active-scope
session remain visible after an outgoing completion so they can be reopened.
Closing preserves the session; unapplied contents are copied to
`unaccepted.md`.

`todomd.changeView` requires a clean accepted buffer. It renders the same
baseline with another resolved view, atomically updates session artifacts, and
requests a workspace edit without entering reconciliation. Clients supporting
`window/showMessageRequest` receive a picker; method-not-found falls back to the
next configured view.

The optional `after_apply` hook runs only after a successful outgoing
transaction. Hook failure is reported but cannot roll back source changes that
already succeeded.

## Scripting boundary

`todomd show` shares repository loading, scope, and projection with editing but
creates no session and runs no hooks. It emits semantic task objects in projected
order, never heading objects. `session apply` provides a scriptable Markdown
write boundary; there is no direct JSON mutation API.

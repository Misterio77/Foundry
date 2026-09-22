# todomd view redesign

## Status

This document describes the intended view system, not the behavior of the
current release. The current command line, configuration, and Markdown format
remain documented in [README.md](README.md).

The redesign separates task meaning from presentation. Every editable property
must be represented by task syntax; headings only make the generated document
easier to scan. The same task can therefore be rendered under different
headings and in different orders without changing its meaning.

## Goals

- Make grouping and sorting independent, configurable parts of a view.
- Allow configuration and command-line options to select or override a view.
- Switch views in a running LSP-backed editing session without touching ICS.
- Keep list membership editable when tasks are not grouped by list.
- Distinguish the singular list from the set of iCalendar categories.
- Preserve hierarchy while sorting and grouping task trees.
- Keep rendering deterministic and parsing unambiguous.

## Invariants

1. ICS remains the source of truth; Markdown remains a session-scoped editing
   surface.
2. Task fields and indentation are authoritative. Headings never change task
   state.
3. A parent and all its descendants belong to one list.
4. A root task and its descendants are an indivisible unit for top-level
   grouping and ordering.
5. View changes are presentation changes. They do not create a transaction,
   run hooks, or modify source files.
6. Task identity remains independent of position, heading text, and view.
7. Equal inputs and an equal view produce byte-identical Markdown.

## Terminology

A **view** consists of:

- an ordered list of grouping keys; and
- an ordered list of sorting keys.

A **group** is a presentation section generated from a root task's values for
one or more grouping keys.

A **task tree** is a root task followed by all of its descendants. Trees move
between groups as units. Descendant siblings are still sorted recursively.

The **active view** is the resolved view used by one command or live session.
It may come from the configured default, a named view, command-line overrides,
or an LSP session change.

## Markdown format

### Task fields

The target canonical form is:

```markdown
- [ ] @Postgrad -2026-09-12 +"2026-09-07 09:00" !!! [Research, "Quick Win"] Write paper <!--t1-->
  - [ ] -2026-09-11 [Reading] Read related work <!--t2-->
```

Canonical leading-field order is:

1. root list;
2. due date;
3. start date;
4. priority;
5. categories; and
6. summary.

Parsing may accept leading fields in any order, as it does today. Rendering
always restores canonical order.

### Lists

A root task carries exactly one list marker:

```markdown
@Postgrad
@"Side Projects"
```

A list name is quoted when necessary using the existing doubled-quote syntax.
A root without a list marker is invalid.

Descendants inherit their parent's list and do not render a redundant list
marker. This keeps trees concise and makes changing one root marker move the
whole tree. A list marker on a descendant is rejected rather than ignored.
Unindenting a child into a root therefore requires adding a list marker, and
indenting a root requires removing its marker.

List membership comes only from the root marker. Moving text beneath a heading
has no effect on it.

### Categories

Categories form one optional bracketed field:

```markdown
[Home]
[Home, Errands]
[Research, "Quick Win", "People, Places"]
```

Category values are separated by commas. A value is quoted when it contains
whitespace, a comma, a bracket, a quote, or leading or trailing whitespace.
Inside quotes, `""` represents a literal quote. Empty values and duplicate
values are invalid. Rendering sorts and deduplicates the category set and
omits the field when the set is empty; `[]` is not canonical input.

This syntax reflects that iCalendar `CATEGORIES` is a set-valued property and
keeps it visually distinct from the singular `@list` marker.

### Summaries and quoting

A summary whose beginning could be parsed as a leading field must be quoted.
This includes summaries beginning with `@`, `[`, `!`, `+`, `-`, or `"`.
Existing edge-whitespace and trailing-identity quoting rules continue to apply.

```markdown
- [ ] @Personal "[not metadata] literal summary"
```

### Headings

Generated headings describe groups but carry no editable meaning:

```markdown
# Postgrad

## High priority

- [ ] @Postgrad !!! Write paper <!--t1-->
```

Heading levels correspond to grouping-key depth. A view with no grouping keys
renders no headings.

The parser accepts headings as presentation separators and does not derive any
task field from their level or text. Adding, deleting, renaming, or moving a
heading therefore changes no task. Headings are discarded and regenerated on
the next canonical render. They do not reset indentation or split a task tree.

The dialect remains otherwise strict: non-heading prose, malformed task lines,
invalid indentation, and unsupported Markdown are errors.

## Grouping

### Keys

The initial groupable fields are:

| Key | Group value | Order |
|---|---|---|
| `list` | root list | selected-list order |
| `completed` | root completion state | unfinished before finished |
| `priority` | root priority bucket | high, medium, low, none |
| `due` | root canonical due value | ascending, missing last |
| `start` | root canonical start value | ascending, missing last |
| `categories` | root's complete canonical category set | lexicographic, missing last |

Grouping by categories uses the complete set as one value. A task is never
duplicated into several groups because duplicate editable identities would make
Markdown ambiguous.

Missing values receive an explicit generated heading such as `No due date` or
`No categories`. Heading labels are presentation strings, not parse tokens.

### Nested groups

Grouping keys are applied left to right. For example:

```toml
group_by = ["priority", "list"]
```

produces priority headings containing list subheadings. The grouping tuple is
an implicit prefix of ordering: groups follow each key's natural order, then
trees within the final group follow `sort_by`.

### Trees

Only roots select top-level groups. Descendants stay adjacent to their root
even when their own field values differ. Within a tree, every sibling set is
sorted recursively using the active sorting keys, and every parent precedes its
descendants.

This rule preserves the Markdown hierarchy and avoids duplicating or detaching
children merely to satisfy a presentation choice.

## Sorting

The sorting keys are:

- `list` (selected-list order);
- `completed`;
- `manual` (`X-APPLE-SORT-ORDER`);
- `due`;
- `start`;
- `priority`; and
- `summary`.

Their existing direction and missing-value behavior remain unchanged. Task
identity is always the final deterministic tie-breaker.

Sorting is view-wide. Per-list sorting overrides are removed because they do
not define a coherent total order when tasks from several lists share a group.
For example, comparing a Postgrad task by due date and a Personal task by
priority would not be transitive.

`manual` remains a sorting key, not a grouping key. It is meaningful primarily
inside list groups but remains deterministic elsewhere.

## Configuration

Views are named records. One name is selected as the startup default:

```toml
default_view = "default"

[views.default]
group_by = ["list"]
sort_by = ["completed", "priority", "summary"]

[views.agenda]
group_by = ["due"]
sort_by = ["due", "priority", "summary"]

[views.priority]
group_by = ["priority", "list"]
sort_by = ["due", "summary"]

[views.flat]
group_by = []
sort_by = ["due", "priority", "summary"]
```

If view configuration is omitted, todomd supplies the current effective
default: group by list and sort by completion, priority, then summary.

Validation rejects:

- an unknown `default_view`;
- unknown grouping or sorting keys;
- duplicate keys within either sequence;
- an empty sorting sequence; and
- unknown keys in a view record.

The old `[sorting]` and `[sorting.lists]` shape is intentionally not part of the
target format. Migration should fail with a focused error that points to the
new view syntax rather than silently changing ordering.

## Command line

Both `edit` and `show` accept view selection and overrides:

```console
todomd edit --view agenda
todomd edit --group-by priority,list --sort-by due,summary
todomd edit --no-group --sort-by due,priority,summary
todomd show --view priority
```

Resolution precedence is:

1. an explicit field override (`--group-by`, `--no-group`, or `--sort-by`);
2. `--view NAME`;
3. the configured `default_view`; and
4. the built-in default.

`--group-by` takes a comma-separated non-empty key sequence. `--no-group`
selects an empty sequence and conflicts with `--group-by`. `--sort-by` takes a
comma-separated non-empty key sequence. `--view` may be combined with field
overrides so a named view can serve as a base.

For `show`, grouping affects task order but emits no heading objects. Every JSON
task already carries its list and field values, so presentation sections do not
belong in the scripting format.

The resolved active view, rather than only its name, is stored in live-session
metadata. A session therefore remains reproducible if configuration changes
while it is open.

## Live view changes

The language server advertises a no-argument `todomd.changeView` workspace
command. On invocation it uses `window/showMessageRequest` to present the
configured views and the built-in default. This avoids depending on arbitrary
workspace-command arguments, which Helix does not currently expose well.

If more than one todomd document is attached to the same language-server
process, the server first asks which session to change. Cancelling either
selection changes nothing.

The first implementation requires the selected document to equal its last
accepted canonical text. If it contains unsaved edits, the command reports
`save or discard changes before switching views`. This prevents a presentation
operation from losing drafts or accidentally approving an ICS transaction.

Changing the active view:

1. validates that the document is at its accepted text;
2. renders the accepted semantic baseline with the selected view;
3. atomically records the resolved active view and accepted document;
4. requests a versioned whole-document workspace edit; and
5. reports the new view without running hooks.

Incoming ICS changes and successful outgoing transactions subsequently render
with the session's active view. Restarting the language server recovers that
view from session metadata.

A failed or rejected workspace edit leaves the previous active view and
accepted text recoverable. Persistence and editor replacement must follow the
same rollback discipline as other live-session artifacts.

## Architecture changes

The repository reader currently produces presentation-ordered task lists. The
redesign introduces an explicit view layer:

```text
ICS repository
    │
    ▼
canonical task forest
    │
    ├── reconciliation and planning
    │
    ▼
resolved view ──▶ grouping and ordering ──▶ Markdown rendering
```

Responsibilities become:

- **Repository:** discover lists, read tasks and manual ranks, resolve scope,
  validate relationships, and return a deterministic canonical forest without
  applying a configured view.
- **View resolver:** combine built-in defaults, configuration, named views, and
  command-line overrides into one validated `View` value.
- **View projector:** group root trees and recursively order siblings without
  changing canonical task meaning.
- **Markdown renderer:** render projected headings and authoritative task
  fields.
- **Markdown parser:** ignore heading meaning, parse root list markers and
  category sets, and reconstruct edited trees from indentation.
- **Live session:** retain the resolved active view and use it for every
  canonical refresh.
- **LSP adapter:** select views and replace a clean open buffer without invoking
  the transaction engine.

Reconciliation compares semantic states only. Heading and ordering differences
never appear in a change plan.

## Migration

This is intentionally a format and configuration break while todomd is still
pre-1.0:

- `@category` becomes `@list` on roots;
- categories move to `[category, ...]`;
- headings stop defining list membership;
- per-list sorting becomes view-wide sorting; and
- live-session metadata gains a format version and resolved active view.

Old retained sessions are not rewritten automatically. Loading incompatible
session metadata should produce a clear error asking the user to reopen the
lists with the new version. Open sessions should be closed before upgrading.

The implementation must update README examples and shell completions in the
same release that changes parsing. It must not temporarily accept ambiguous
`@name` tokens as either a category or a list based on whether the name happens
to match a selected list.

## Implementation plan

### 1. Authoritative task syntax

- Add root list markers and bracketed category parsing/rendering.
- Make headings semantically inert.
- Validate root/descendant list invariants.
- Update parser, renderer, planner, and lifecycle tests for moves, nesting,
  quoting, and malformed input.
- Version live-session metadata and reject old sessions clearly.

### 2. View model and projection

- Add validated `GroupKey`, `SortKey`, and `View` types.
- Move ordering out of repository loading.
- Project task forests into nested groups while keeping trees atomic.
- Apply recursive sibling sorting and deterministic tie-breakers.
- Test every key, missing-value bucket, nested grouping, and category-set
  grouping.

### 3. Configuration and CLI

- Replace per-list sorting configuration with named views.
- Add default-view resolution and command-line overrides.
- Apply view ordering consistently to `edit` and `show`.
- Generate updated Bash, Fish, and Zsh completions.
- Update README and examples to describe the shipped behavior.

### 4. Live switching

- Store the resolved active view in session metadata.
- Implement `todomd.changeView` and client selection prompts.
- Reject dirty-buffer switches safely.
- Persist and roll back view/document artifacts atomically.
- Test LSP restart, inbound refresh, rejected workspace edits, multiple
  attached documents, and no-hook/no-transaction behavior.

Each phase should leave tests passing and avoid a state where Markdown can be
parsed with two different meanings. Phases may land separately only if the
intermediate format is not exposed as a supported release.

## Future improvements

### Dirty-buffer view changes

Support switching views without saving by rendering `EditedTaskState`,
including draft identities and unsaved hierarchy changes. This must preserve
all edits without treating the switch as transaction approval.

### Derived date groups

Add useful agenda buckets such as overdue, today, tomorrow, this week, later,
and undated. These are derived, time-dependent values rather than raw task
fields, so the session must define when they are recomputed and how an open
buffer crosses a date boundary.

### Persistent manual ordering

Make Markdown sibling order writable through sparse
`X-APPLE-SORT-ORDER` ranks. Rebalancing must account for hidden completed roots
and descendants, and presentation-only view changes must remain distinguishable
from intentional manual reordering.

### Richer LSP view controls

Possible additions include next/previous-view commands, a status notification,
code actions scoped to one document, and completion for list and category
fields. These should supplement named views rather than encode editor-specific
protocols.

### Group-label customization

Allow localized or user-defined labels for missing values and derived groups.
Labels remain output-only and must never become parse authority.

### Session preference persistence

Optionally remember the last selected named view for later sessions. This must
be explicit; merely switching one temporary session should not silently rewrite
configuration.

### Additional language features

Completion, hover, document symbols, repair code actions, and richer conflict
recovery can build on the authoritative field grammar. A list inventory command
remains useful for scripts and for discovering values accepted by `@list`.

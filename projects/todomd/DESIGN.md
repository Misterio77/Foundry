# todomd design

## Goal

Edit local, vdir-backed VTODO lists through a temporary Markdown document. A
user selects whole lists, edits their tasks, reviews the resulting semantic
change plan, and applies it to the source `.ics` files.

The `.ics` files are the source of truth. Markdown is a session-scoped editing
surface, not a second task store. `todomd` does not speak CalDAV; synchronizing
the vdirs is an independent concern reached through hooks.

The current driver is one-shot. The core supports repeated transactions so a
later `edit --watch` can synchronize both directions without replacing it.

## Scope

Supported:

- selecting whole lists by display name;
- creating, renaming, nesting, prioritizing, completing, reopening, moving, and
  deleting tasks;
- previewing and confirming a semantic change plan;
- preserving iCalendar data the Markdown does not expose;
- detecting source changes made during a session;
- staging, backup, and best-effort rollback;
- hooks around the session and after an apply; and
- a read-only JSON view.

Not supported:

- CalDAV, or controlling synchronization software directly;
- editing categories, descriptions, recurrence, or alarms;
- persistent task ordering;
- silently merging concurrent semantic edits; or
- general-purpose iCalendar editing.

Deferred: due and start dates, watch mode, automatic crash recovery. Adding
date fields must not disturb existing date properties.

## Principles

1. **Model tasks, not files.** Plans describe task operations; paths appear in
   the preview for safety only.
2. **Preserve what is not exposed.** Editing a summary must not discard an
   alarm, recurrence rule, relationship, or vendor property.
3. **Plan before mutation.** Parsing, validation, reconciliation, and staging
   finish before any source file changes.
4. **Treat concurrency as normal.** Every transaction compares both sides
   against a last-agreed baseline.
5. **Keep drivers thin.** Editor exit and filesystem events trigger
   transactions; they contain no synchronization logic.
6. **Assume repeated transactions.** The core never assumes one parse or apply
   cycle per session.
7. **Reject ambiguity.** Invalid Markdown, unknown identities, duplicate lists,
   and concurrent edits stop the transaction.

## Architecture

```text
                 ┌──────────────────────┐
ICS repository ─▶│                      │
                 │   canonical model    │
Markdown codec ─▶│                      │
                 └──────────┬───────────┘
                            │
                 baseline / Markdown / ICS
                            │
                            ▼
                    reconciliation planner
                            │
                         change set
                            │
                  validation and staging
                            │
                            ▼
                         applier

one-shot driver ─┐
                 ├─ trigger the same transaction engine
watch driver ────┘
```

| Component | Responsibility |
|---|---|
| Canonical model | Editable meaning only: list identity, task identity, parent identity, list membership, summary, completion state |
| Source snapshot | Patch context: source paths, raw file hashes, parsed objects, unexposed properties |
| ICS repository | Discovers lists, reads VTODOs, patches objects, stages and applies filesystem operations |
| Markdown codec | Deterministic rendering and strict parsing |
| Reconciliation planner | Classifies divergence and produces a change set |
| Transaction engine | Validates, stages, applies, and advances the baseline |
| Drivers | Own interaction and event policy |

The canonical model holds no paths, raw files, parsed iCalendar objects, editor
state, or watcher state, which keeps baselines and planning format-independent.
The source snapshot carries that material separately, so raw hashes can guard
application against changes the model and Markdown do not represent.

Module layout follows this split: `config`, `model`, and `repository` are
shared; each subcommand is a directory, with the editing machinery under
`edit/`.

## Commands

Modes are subcommands, so each carries only the options that apply to it and a
later `--watch` flag on `edit` needs no mode exclusions.

| Command | Effect |
|---|---|
| `todomd` | Edit every discovered list |
| `todomd edit [LISTS]...` | Edit the named lists, with `--no-hooks` and `--keep` |
| `todomd show [LISTS]...` | Print tasks as JSON |

Both subcommands take `--completed`, which widens the task set from active-root
trees to every task.

Lists are positional only inside a subcommand. The top level takes no list
arguments, so a list sharing a subcommand's name stays addressable and an
unknown verb is reported rather than read as a list name.

Omitting list names selects every discovered list, ordered by display name. A
command resolves that set once and reuses it, so a list appearing mid-session
cannot become a spurious inbound change.

`show` is the read surface for scripts and agents. It emits a JSON array of
tasks, each with its list, UID, summary, completion flag, priority, rendered
parent UID, and absolute source file, and performs no session, editor, hook, or
terminal work. The file is
required because vdir item filenames are chosen by whatever created them, so a
UID cannot be mapped to a path without reading the collection.

`show` has no write counterpart. Fields the Markdown does not expose are edited
in the `.ics` directly, which suits both scripts and a deliberately narrow
Markdown dialect.

## List discovery

Configuration holds one or more vdir roots. Immediate child directories are
candidate lists, matched by the content of their `displayname` file rather than
their directory name.

Missing names, duplicate display names, unreadable lists, and malformed VTODO
files are reported before the document opens. A file is never silently omitted
from a selected list: parse failures abort, and valid tasks that cannot be
rendered are reported.

One primary VTODO per `.ics` file is supported. Auxiliary components in the file
are preserved.

## Task scope

A command operates on active root trees or, with `--completed`, on every task.
Completed and cancelled tasks are one set, and both render as `[x]`. The default
scope includes a finished subtask when all of its ancestors are active, then
stops before that subtask's descendants. A finished root therefore hides its
full descendant subtree, and a task never appears without its parent.

The scope is resolved once and reused for the initial read, the reread after the
editor exits, and the accepted-state refresh. Reading a different set at any of
those points would turn tasks outside the scope into phantom deletions.

`SUMMARY` is optional in RFC 5545, so a task without one is valid but has no
Markdown representation. Such a task and its descendant subtree are excluded
from every scope, regardless of completion, and the task is reported on stderr
rather than failing the command or vanishing silently. They stay editable
through their `.ics` files.

Status is never rewritten unless the checkbox changes, so a cancelled task keeps
its status unless it is explicitly reopened.

## Markdown format

```markdown
# Postgrad

- [ ] !!! Write paper draft <!-- todomd:id=t1 -->
  - [ ] Email advisor

# Personal

- [ ] ! Buy groceries <!-- todomd:id=t3 -->
```

A task line is a checkbox, an optional priority marker, a summary, and an
optional identity marker. `!!!`, `!!`, and `!` are high, medium, and low; an
absent marker is no priority.

Within each sibling set, tasks render unfinished first, then by descending
priority, then alphabetically by summary, with the task identity breaking ties.
A parent precedes its recursively sorted descendants, so the same state always
renders identically. Sorting finished siblings last keeps the wider scope
usable when a list holds one open task among hundreds.

Sibling ordering carries no meaning: it is presentational, and reordering lines
is not a change. Indentation alone carries hierarchy. Because Markdown flattens
nine iCalendar priorities into three levels, sibling tasks stored as
`PRIORITY:1` and `PRIORITY:4` interleave alphabetically.

Each selected list appears exactly once as a level-one heading. Existing tasks
carry opaque, session-local IDs mapped to source identities by the manifest.
Session IDs rather than raw VTODO UIDs avoid leaking or misparsing arbitrary UID
contents. A task without an ID is new.

In the default scope active roots and their descendants render. Completed
subtasks render checked, and traversal stops below them. Tasks outside the
current scope are absent from the document, so their absence is never read as
deletion. An unchanged `IN-PROCESS` task stays `IN-PROCESS`; unchecked syntax
alone does not normalize it to `NEEDS-ACTION`.

| Markdown edit | Operation |
|---|---|
| Change task text | Rename |
| Add or change `!`, `!!`, `!!!` | Set priority |
| Remove the priority marker | Clear priority |
| Change `[ ]` to `[x]` | Complete |
| Change `[x]` to `[ ]` | Reopen |
| Add an item without an ID | Create in the containing list |
| Indent an item | Set its parent to the preceding item one level up |
| Unindent or reindent an item | Detach or reparent it |
| Move an item or nested block under another heading | Move those tasks to that list |
| Remove an identified item | Delete that VTODO only |
| Reorder siblings | No change |

Task-list items use exactly two spaces per nesting level and may nest to
arbitrary depth. A task cannot skip a level or have a parent in another list.
Blank lines are insignificant. Additional headings, missing or renamed selected
headings, duplicate or unknown IDs, malformed indentation or checkboxes, empty
summaries, and unsupported Markdown are parse errors.

Deleting a parent line deletes only that VTODO. Removing its nested block also
deletes each child line; retaining and unindenting a child explicitly detaches
it. Moving a nested block moves every represented task. Completion is
independent of hierarchy, so a parent may be completed while children remain
open.

### Quoting

A summary is quoted only when reading it back would otherwise be ambiguous: when
it starts with `!` or `"`, or when leading or trailing whitespace would be lost.
Inside quotes a literal `"` is doubled, so the dialect needs no second escape
character.

The summary's right edge is already delimited by the identity marker, so only
its first character can be ambiguous. Interior quotes are therefore left alone
and ordinary prose never acquires quoting. An unquoted summary that starts with
a reserved character is a parse error rather than a guess.

This generalizes: fields added later can reserve leading syntax without
inventing their own escape.

New tasks receive draft identities in document order during parsing. Parent
references may name either an existing task or an earlier draft at the preceding
indentation level. Planning allocates every new VTODO UID before staging any
file, so arbitrarily nested new trees can be written in any plan order. After a
successful apply, `tasks.md` is rerendered atomically with session IDs, so a
later transaction cannot mistake a task for another creation.

## Reconciliation

The planner receives three semantic states: the **baseline** last known to agree
on both sides, the parsed **Markdown**, and a fresh read of the selected
**ICS** lists.

| Markdown vs baseline | ICS vs baseline | Classification |
|---|---|---|
| unchanged | unchanged | no change |
| changed | unchanged | Markdown-to-ICS plan |
| unchanged | changed | ICS-to-Markdown update |
| changed | changed | conflict |

The one-shot driver applies Markdown-to-ICS plans. If ICS changed while the
editor was open it reports the external change and retains the session instead
of applying stale edits. A watch driver would also consume ICS-to-Markdown
updates.

Semantic changes on both sides are a conflict even when they appear unrelated.
Per-task merging could be added later without changing the planner's inputs.

A raw ICS change that alters no editable semantics refreshes source metadata
only. It must not force a Markdown rewrite, and an outgoing apply may proceed
only against the refreshed source object.

## Transactions

A transaction is callable without an editor process. It:

1. reads the Markdown document and the selected vdirs;
2. parses both into canonical states;
3. reconciles them against the baseline;
4. validates the result and builds a semantic change set;
5. stages every filesystem operation;
6. delegates approval to the driver's policy;
7. applies the approved stage;
8. rerenders accepted Markdown when identities were added or changed;
9. advances the baseline and source snapshot; and
10. runs any post-apply hook.

A failure before application leaves the previous baseline valid. A post-apply
hook failure does not undo valid local changes or their new baseline.

### Application safety

Each initial read records the membership and raw content hashes of every file in
the selected lists, including data absent from Markdown. Immediately before
application, the applier rechecks that list identity, membership, and all raw
hashes still match the snapshot the stage was built from, and rechecks each
operation's own inputs before running it.

Replacements are written to temporary files on the destination filesystem and
renamed into place. Originals are copied into the transaction's `backup/`
directory before being replaced, moved, or deleted. Moves keep the source
filename; a destination collision fails the transaction rather than overwriting.

A change spanning several files cannot be truly atomic. If an operation fails
after mutation begins, `todomd` rolls back under the same hash guards, retains
the session, and reports both the original and rollback failures. It never
intentionally applies part of a plan. Process or machine failure can still
interrupt rollback; the retained stage and backups support manual recovery, but
automatic crash recovery is not claimed.

Hash checks reduce but cannot eliminate a race with an uncooperative concurrent
writer. A `before_session` hook can pause one. Watch mode instead relies on
short transactions, fresh reads, and explicit conflict handling.

### Session storage

Sessions are private `0700` directories below `$XDG_RUNTIME_DIR/todomd`, falling
back to the system temporary directory:

```text
session-XXXXXX/
├── tasks.md
├── manifest.json
├── baseline.json
└── transactions/
    └── 0001/
        ├── plan.json
        ├── staged/
        └── backup/
```

Numbering supports multiple transactions even though the one-shot driver
triggers one. Rejected, conflicted, and failed sessions are retained and their
paths printed; others are removed unless `--keep` is given. Backups contain task
data and inherit the private permissions.

## Approval

The plan reports semantic operations and every affected path:

```text
Postgrad:
  renamed   Write paper -> Write paper draft
  completed Read chapter four
  created   Email advisor

Personal:
  deleted   Buy cursed ornamental cabbage

Files:
  modify ~/Calendars/personal/Postgrad/4bdc.ics
  delete ~/Calendars/personal/Personal/cabbage.ics
  create ~/Calendars/personal/Postgrad/<generated>.ics

Apply these changes? [y/N]
```

Confirmation requires an interactive terminal and an explicit `y`. Empty input
rejects the plan. There is no unattended one-shot apply. Watch mode would use a
different policy, where opting in makes a valid save its own approval.

Discovery, hook, editor, parsing, conflict, staging, and application failures
exit non-zero. Rejecting a plan is a successful cancellation. The post-session
hook's result is reported separately so it cannot hide a primary failure.
Signals that cannot be handled, notably `SIGKILL`, cannot promise cleanup.

## iCalendar handling

Existing files are patched, never rebuilt from Markdown fields, preserving:

- due and start dates;
- categories;
- descriptions;
- alarms and recurrence;
- unchanged `RELATED-TO` representations;
- time zone components; and
- vendor-specific properties.

Files untouched by a change set are not rewritten. Patched components are
serialized through a typed writer so edited `TEXT` values are escaped.

Changing an existing task increments `SEQUENCE` and updates `DTSTAMP` and
`LAST-MODIFIED`. Completion sets `STATUS`, `COMPLETED`, and `PERCENT-COMPLETE`
consistently; reopening sets `STATUS` to `NEEDS-ACTION` and removes `COMPLETED`
and `PERCENT-COMPLETE`. Source filenames and VTODO UIDs are independent
identities.

`RELATED-TO` without `RELTYPE`, and `RELATED-TO;RELTYPE=PARENT`, both name a
parent. Other relationship types are preserved but do not affect indentation.
Empty and dangling values render as roots and stay untouched unless the item is
reindented. Identical duplicate parent properties are accepted and
preserved through unrelated edits; conflicting values and relationship cycles
abort the read. An explicit relationship change updates or removes the property.

`PRIORITY` is 1-9 in iCalendar but three levels in Markdown: 1-4 read as `!!!`,
5 as `!!`, 6-9 as `!`, and anything absent or out of range as no marker. A value
is written only when the level changes, so a task stored as `PRIORITY:4` keeps
that value through edits that leave its marker alone. Clearing the marker
removes the property; setting one writes the canonical 1, 5, or 9.

## Hooks

Configuration lives at `$XDG_CONFIG_HOME/todomd/config.toml`, falling back to
`~/.config/todomd/config.toml`. Paths support home-directory expansion. Hooks
are argument arrays executed directly, never shell strings.

| Hook | Contract |
|---|---|
| `before_session` | Runs once before any list is read; failure aborts the command |
| `after_apply` | Runs only after source files changed; failure does not roll back |
| `after_session` | Runs on every exit once `before_session` succeeded, including cancellation, failure, and handled termination signals |

Session-lifetime pause hooks do not suit a long-running watch process. Watch
mode would run neither `before_session` nor `after_session`, only `after_apply`
after each successful transaction.

## Deferred watch mode

`edit --watch` would apply valid Markdown saves automatically, rerender when the
selected vdirs change, keep the editor open across transactions, and retain
transaction artifacts for recovery. Saving becomes approval, so it stays opt-in
and one-shot remains the default.

The watcher observes parent directories rather than existing inodes, because
editors and synchronization tools commonly save by temporary-file rename. Events
are debounced and reduced to content and semantic hashes; self-generated events
matching the accepted transaction are ignored.

On a Markdown save it parses the document, reads fresh ICS state, reconciles,
applies a valid outgoing plan, rerenders generated identities, advances the
baseline, and runs `after_apply`. An invalid intermediate save changes nothing
and a later valid save retries.

On an ICS change it validates the new state, reconciles against saved Markdown,
and atomically replaces `tasks.md` for an ICS-only change. Unsaved editor buffer
contents are invisible to `todomd`; the replacement makes editors report a
diverged buffer.

If both sides changed since the baseline, neither is rewritten or applied and
the conflict awaits explicit resolution.

The architecture already satisfies what this requires: rendering, parsing, and
the repository have no editor or watcher dependencies, transactions can run
repeatedly against an updated baseline, approval is driver policy, inbound and
outbound divergence share one classification, and session storage is numbered.

## Deferred decisions

- compatibility rules for recurring VTODOs and unusual multi-component files;
- session manifest migration policy;
- event-watching abstraction;
- durable crash-recovery protocol;
- watch-mode conflict and recovery commands; and
- whether per-task merging is worthwhile.

# todomd design

## Purpose

`todomd` edits local, vdir-backed VTODO lists through Markdown. A user selects
one or more whole lists, edits their tasks in a temporary document, reviews the
semantic changes, and applies those changes back to the source `.ics` files.

```console
$ todomd Postgrad Personal
```

The `.ics` files remain the source of truth. Markdown is a session-scoped
editing surface, not another persistent task store. `todomd` does not speak
CalDAV; synchronization software such as vdirsyncer remains an independent
concern.

The first release is deliberately one-shot. Its internals must nevertheless
support repeated synchronization transactions so a later `--watch` driver can
synchronize Markdown and ICS in both directions without replacing the core.

## Product boundaries

### MVP

The MVP supports:

- selecting multiple complete lists by display name;
- creating tasks;
- editing summaries;
- completing and reopening tasks;
- deleting tasks;
- moving tasks between the selected lists;
- previewing and confirming a semantic change plan;
- preserving iCalendar data not exposed in Markdown;
- detecting source changes made during an editing session;
- staging, backup, and best-effort rollback; and
- optional hooks around the one-shot session and after a successful apply.

### Next field extension

Due and start dates are the first planned editable fields after the MVP. Their
absence from the initial Markdown format must not remove or alter existing date
properties.

### Deferred watch mode

A later explicit `--watch` mode will:

- apply valid Markdown saves automatically;
- rerender Markdown when selected vdirs change;
- keep the editor process open across transactions;
- detect changes made independently on both sides;
- rely on the editor to surface divergence from unsaved buffer contents; and
- retain transaction artifacts for inspection and manual recovery.

Watch mode is opt-in because saving becomes approval to change the vdirs. The
one-shot mode remains the default and retains interactive confirmation.

### Non-goals

The initial project will not:

- communicate with a CalDAV server;
- require or directly control vdirsyncer;
- edit priorities, categories, descriptions, recurrence, alarms, or task
  relationships;
- assign a persistent ordering to tasks;
- silently merge concurrent semantic edits; or
- serve as a general-purpose iCalendar editor.

## Design principles

1. **Model tasks, not files.** Diffs describe task operations; filesystem paths
   are an application detail shown for safety.
2. **Preserve what is not exposed.** Editing a summary must not discard an alarm,
   recurrence rule, relationship, or vendor property.
3. **Plan before mutation.** Parsing, validation, reconciliation, and staging all
   finish before source files change.
4. **Treat concurrency as normal.** Every transaction compares both sides with a
   last-agreed baseline.
5. **Keep drivers thin.** Editor exit and filesystem notifications only trigger
   transactions; they do not contain synchronization logic.
6. **Make repeated transactions possible immediately.** The core cannot assume
   that a session has exactly one parse or apply cycle.
7. **Reject ambiguity.** Invalid Markdown, unknown identities, duplicate lists,
   and concurrent edits stop the transaction rather than inviting guesses.

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
                 ├─ triggers the same transaction engine
watch driver ────┘
```

### Canonical model

The canonical model represents only the editable meaning shared by both
formats:

- selected list identity and display name;
- task identity;
- list membership;
- summary; and
- completion state.

It contains no paths, raw files, parsed iCalendar objects, editor state, or
watcher state. The model has a deterministic semantic representation and hash
used by reconciliation.

### Source snapshot

A separate source snapshot maps canonical identities to the material needed to
patch the vdirs safely: source paths, raw file hashes, original iCalendar
objects, and properties outside the MVP. Raw hashes guard application against
changes that the canonical model and Markdown do not expose.

Keeping patch context outside the canonical model allows baselines and planners
to remain format-independent. The applier receives both a semantic change set
and the fresh source snapshot from which its stage was built.

### ICS repository

The ICS repository:

- discovers lists below configured roots;
- resolves display names through each list's `displayname` file;
- reads VTODO components and source metadata;
- produces canonical models and separate source snapshots;
- patches existing objects without rebuilding them from Markdown fields;
- stages new, modified, moved, and deleted files; and
- applies staged filesystem operations with raw-hash guards.

It does not invoke the editor, ask for confirmation, watch directories, or make
synchronization policy decisions.

### Markdown codec

The Markdown codec is responsible only for deterministic rendering and strict
parsing. Rendering the same canonical model with the same identity manifest
must produce the same document. Parsing does not read ICS files or infer missing
identities from summaries.

### Reconciliation planner

The planner receives three semantic states:

- **baseline:** the last state known to agree on both sides;
- **Markdown:** the current parsed document; and
- **ICS:** a fresh read of the selected source lists.

It classifies divergence before producing a change set:

| Markdown vs baseline | ICS vs baseline | Classification |
|---|---|---|
| unchanged | unchanged | no change |
| changed | unchanged | Markdown-to-ICS plan |
| unchanged | changed | ICS-to-Markdown update |
| changed | changed | conflict |

The MVP one-shot driver uses the Markdown-to-ICS plan. If ICS changed while the
editor was open, it reports the external change and retains the session instead
of applying stale edits. The future watch driver also consumes
ICS-to-Markdown updates.

The first implementation treats any semantic changes on both sides as a
conflict, even when they appear unrelated. Per-task automatic merging may be
added later without changing the planner's inputs.

A raw ICS change that does not alter editable semantics still refreshes source
metadata. It must not cause an unnecessary Markdown rewrite, but an outgoing
apply may proceed only against the refreshed source object after validating that
the intended patch remains safe.

### Transaction engine

A transaction is callable independently of an editor process. It:

1. reads the current Markdown document;
2. reads the current selected vdirs;
3. parses both into canonical states;
4. reconciles them against the baseline;
5. validates the complete result;
6. constructs a semantic change set;
7. stages all filesystem operations;
8. delegates approval to the driver policy;
9. applies the approved stage;
10. renders the accepted result back to Markdown when machine identities were
    added or changed;
11. advances the semantic baseline and source snapshot after a successful local
    apply or accepted inbound update; and
12. runs any configured post-apply hook after a local apply.

New tasks receive identities during planning. After their ICS files are applied,
the accepted canonical result is atomically rendered back to `tasks.md`, so the
new session IDs are present before another transaction can parse the document.
The resulting self-write is identified by its accepted hash and ignored by a
future watch driver.

A failure before local application leaves the previous baseline valid. A
post-apply hook failure does not undo valid local changes or their new baseline;
a later transaction can continue from the locally accepted state.

### Drivers

Drivers own interaction and event policy, not data conversion.

The one-shot driver:

- creates the session;
- performs the initial render;
- invokes the editor;
- triggers one transaction after a successful editor exit;
- prints the plan;
- asks for confirmation; and
- cleans up or retains the session.

The future watch driver:

- watches the Markdown session directory and selected list directories;
- debounces and classifies events;
- triggers the same transaction engine repeatedly;
- automatically approves valid Markdown-to-ICS plans;
- atomically writes accepted ICS-to-Markdown updates; and
- reports conflicts without overwriting either saved side.

## List discovery

The configuration contains one or more vdir roots. Immediate child directories
are candidate lists. A list argument matches the content of its `displayname`
file, not its directory name.

Missing names, duplicate display names, unreadable lists, and malformed
supported VTODO files are reported before the initial Markdown document opens.
`todomd` never silently omits a file from a selected list merely because parsing
it failed.

The MVP supports one primary VTODO per `.ics` file. Auxiliary components needed
by that VTODO may remain in the file and must be preserved. Exact compatibility
rules for recurring VTODOs and unusual multi-component files will be fixed when
selecting the iCalendar library.

## Markdown format

A rendered session resembles:

```markdown
# Postgrad

- [ ] Write paper draft <!-- todomd:id=t1 -->
- [x] Read chapter four <!-- todomd:id=t2 -->
- [ ] Email advisor

# Personal

- [ ] Buy groceries <!-- todomd:id=t3 -->
```

Each selected list appears exactly once as a level-one heading. Existing tasks
carry opaque, session-local IDs mapped to source identities by the manifest.
Using session IDs rather than raw VTODO UIDs avoids leaking or misparsing
arbitrary UID contents. A task without an ID is new.

Only top-level task-list items are editable in the MVP. Blank lines are
insignificant. Additional headings, missing or renamed selected headings,
duplicate or unknown IDs, malformed checkboxes, and unsupported Markdown are
parse errors. Task ordering has no semantic effect.

Active tasks render unchecked. Completed tasks render checked so they can be
reopened. Cancelled tasks are not editable in the MVP and remain untouched. An
unchanged `IN-PROCESS` task remains `IN-PROCESS`; unchecked syntax alone does not
normalize it to `NEEDS-ACTION`.

### Edit semantics

| Markdown edit | Semantic operation |
|---|---|
| Change task text | Rename task |
| Change `[ ]` to `[x]` | Complete task |
| Change `[x]` to `[ ]` | Reopen task |
| Add an item without an ID | Create task in the containing list |
| Move an identified item beneath another heading | Move task to that list |
| Remove an identified item | Delete task |
| Reorder items | No change |

A new task receives a VTODO UID and session ID while planning and staging.
After a successful apply, `tasks.md` is rerendered atomically with that session
ID so a later transaction cannot mistake the task for another creation. Empty
summaries are rejected.

## One-shot MVP lifecycle

The command is:

```text
todomd [OPTIONS] LIST...
```

Provisional options are:

```text
--config PATH   use a specific configuration file
--keep          retain the session after a successful run
--no-hooks      disable configured hooks for this run
```

The lifecycle is:

1. Create a private session directory.
2. Run the configured `before_session` hook.
3. Discover and validate the requested lists.
4. Read the initial ICS state as the baseline.
5. Render the baseline to Markdown.
6. Invoke `$VISUAL`, falling back to `$EDITOR`.
7. If the editor exits successfully, run one synchronization transaction.
8. If there is an outgoing plan, display its semantic and filesystem effects.
9. Ask `Apply these changes? [y/N]`.
10. Apply only after an explicit `y`.
11. Update the manifest, Markdown machine IDs, baseline, and source snapshot.
12. Run `after_apply` following a successful source apply.
13. Run `after_session` on every exit path after `before_session` succeeds.

A missing editor or non-zero editor exit does not produce a plan. An empty
semantic diff exits successfully without a confirmation prompt.

If only ICS changed while the editor was open, the one-shot command reports the
external update without rewriting the edited document. If both sides changed,
it reports a conflict. Both cases retain the session for inspection.

## Session storage

Sessions are private directories with mode `0700` below
`$XDG_RUNTIME_DIR/todomd`, falling back to the system temporary directory:

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

The layout supports multiple transactions even though the MVP driver triggers
only one. Transaction numbering, manifests, and baseline replacement must not
assume one-shot operation.

Rejected, conflicted, and failed sessions are retained and their paths printed.
Successful sessions are removed unless `--keep` is used. Backups contain task
data and inherit the private session permissions.

## Change preview and approval

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
rejects the plan. The MVP has no unattended one-shot apply option.

Watch mode will use a different approval policy: selecting `--watch` explicitly
opts into automatic application after every valid Markdown save.

## iCalendar preservation

Existing files are never reconstructed solely from Markdown fields. The ICS
repository patches the original parsed object and preserves unexposed
properties, including:

- due and start dates;
- priorities and categories;
- descriptions;
- alarms and recurrence;
- `RELATED-TO` relationships;
- time zone components; and
- vendor-specific properties.

Files untouched by a change set are not rewritten. Changed files may be
reserialized by the selected library, but unexposed data must remain
semantically equivalent.

An existing task change increments `SEQUENCE` and updates the appropriate
modification timestamp. Completion and reopening update `STATUS`, `COMPLETED`,
and relevant progress properties consistently. Exact normalization rules are
chosen and tested alongside the iCalendar library.

Source filenames and VTODO UIDs are independent identities. Moves preserve the
source filename unless it collides in the destination, in which case staging
fails before source mutation.

## Application safety

Every initial read records the membership and raw content hashes of all files in
each selected list, including data not represented in Markdown. Staging uses
freshly read source objects. Immediately before application, the applier checks
that the complete selected-list membership and all raw hashes still match the
source snapshot used to construct the stage.

All validation and staging complete before approval. Replacements are written
to temporary files on the destination filesystem and renamed into place.
Originals are copied into the transaction's `backup/` directory before they are
replaced, moved, or deleted.

A change spanning several files or directories cannot be truly atomic. If an
operation fails after mutation begins, `todomd` attempts rollback, retains the
session, and reports both the original and rollback failures. It never
intentionally applies only the valid subset of a plan. Process or machine failure
can also interrupt rollback; the retained stage and backups support manual
recovery, but automatic crash recovery is not an MVP claim.

Raw hash checks reduce but cannot eliminate a race with an uncooperative writer
between verification and multiple filesystem operations. A `before_session`
hook can pause such a writer in one-shot mode. Watch mode instead expects short
transactions, fresh reads, optimistic guards, and explicit conflict handling.

## Hooks

The default configuration path is
`$XDG_CONFIG_HOME/todomd/config.toml`, falling back to
`~/.config/todomd/config.toml`.

Example:

```toml
calendar_roots = ["~/Calendars/personal"]

[hooks]
before_session = [
  "systemctl", "--user", "stop",
  "vdirsyncer.timer", "vdirsyncer.service",
]
after_session = [
  "systemctl", "--user", "start",
  "vdirsyncer.timer",
]
after_apply = [
  "systemctl", "--user", "start",
  "vdirsyncer.service",
]
```

Paths support home-directory expansion. Hooks are argument arrays executed
directly, never shell strings.

If `before_session` fails, the command aborts. Once it succeeds,
`after_session` runs on cancellation, editor failure, parse failure, conflict,
application failure, and handled termination signals. An `after_apply` failure
does not roll back already valid local changes; it is reported as a
synchronization-hook failure and produces a non-zero exit.

Session-lifetime pause hooks are unsuitable for a long-running watch process.
Watch mode will not run `before_session` or `after_session`; it may run
`after_apply` after each successful Markdown-to-ICS transaction.

## Future bidirectional watch driver

The future interface is:

```console
todomd --watch Postgrad Personal
```

The watcher observes parent directories rather than only existing file inodes,
because editors and synchronization tools commonly save by temporary-file
rename. Events are debounced, then reduced to content and semantic hashes.
Self-generated events whose resulting hashes match the accepted transaction are
ignored.

### Markdown save

When `tasks.md` changes, the driver:

1. waits for the write burst to settle;
2. parses the complete document;
3. reads fresh ICS state;
4. reconciles both with the baseline;
5. automatically applies a valid Markdown-to-ICS plan;
6. rerenders any generated machine identities into `tasks.md`;
7. advances the baseline and source snapshot; and
8. runs `after_apply`.

An invalid intermediate save prints an error and changes neither ICS nor the
baseline. A later valid save retries normally.

### ICS change

When a selected list changes, the driver:

1. waits for the write burst to settle;
2. reads and validates the complete selected ICS state;
3. parses the saved Markdown document;
4. reconciles both with the baseline;
5. atomically replaces `tasks.md` for an ICS-only change; and
6. advances the baseline and source snapshot.

If the editor buffer has unsaved changes, those changes are invisible to
`todomd`. The atomic replacement changes the file on disk; editors such as Helix
then report that the buffer diverged and let the user reload or resolve it.

If saved Markdown and ICS both changed since the baseline, `todomd` does not
rewrite or apply either side. It reports a conflict and waits for explicit user
resolution. Exact watch-mode conflict commands and recovery UX are deferred.

## Exit behavior

Discovery, hook, editor, parsing, conflict, staging, and application failures
produce non-zero exits. Rejecting a one-shot plan is a successful cancellation
and exits zero after printing the retained session path.

The post-session hook's result is reported separately so it cannot hide the
primary failure. Signals that cannot be handled, notably `SIGKILL`, cannot
promise hook execution or cleanup.

## Architectural acceptance criteria

The MVP architecture is ready for a watch driver when:

- Markdown rendering and parsing have no editor or watcher dependencies;
- the ICS repository has no confirmation or event-loop dependencies;
- a transaction can be invoked repeatedly in one process with an updated
  baseline;
- tests can exercise two consecutive transactions without launching an editor;
- the one-shot driver supplies approval as policy rather than embedding it in
  the applier;
- inbound and outbound divergence are classified from the same three states;
- session storage can contain multiple numbered transactions; and
- no core API assumes that editor exit caused the change.

## Deferred implementation decisions

Implementation work still needs to select:

- language and iCalendar library;
- exact component compatibility rules;
- timestamp, progress, and `SEQUENCE` normalization;
- semantic and raw hashing formats;
- session manifest schema and migration policy;
- event-watching abstraction;
- durable crash-recovery protocol;
- watch-mode conflict and recovery commands; and
- whether per-task three-way merging is eventually worthwhile.

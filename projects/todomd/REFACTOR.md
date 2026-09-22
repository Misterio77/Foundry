# Session refactor plan

## Purpose

The explicit session lifecycle and LSP now share reconciliation and transaction
application through `src/edit/session_reconcile.rs`. The remaining duplication
is around session creation, accepted-state rendering/persistence, result
summaries, CLI argument definitions, and stale live-only names.

This refactor should make the two workflows thin adapters over the same core:

```text
                         ┌─▶ manual CLI adapter ─▶ canonical tasks.md
session creation ─▶ reconciliation/application
                         └─▶ LSP adapter ─────────▶ workspace edit
```

The goal is not fewer lines at any cost. The goal is one implementation for
each semantic operation, with manual and LSP code responsible only for their
different I/O.

## Current baseline

The implementation immediately before this plan has:

- `todomd edit` as the opinionated editor + LSP workflow;
- `todomd session create/apply/close` as the editor-independent workflow;
- one shared reconciliation/application engine in
  `src/edit/session_reconcile.rs`;
- an exclusive session lock shared by manual commands and LSP;
- session format version 3;
- 146 passing tests, Clippy with warnings denied, rustfmt, and a successful Nix
  build.

Relevant modules:

| File | Current responsibility |
|---|---|
| `src/edit/mod.rs` | Edit options, repository rendering, top-level live edit entry point |
| `src/edit/live.rs` | Create a session, open the editor, enforce LSP attachment |
| `src/edit/session_commands.rs` | Manual create/apply/close adapters |
| `src/edit/session.rs` | Session artifacts, locking, loading, atomic replacement |
| `src/edit/session_reconcile.rs` | Shared parse/reconcile/apply engine |
| `src/lsp.rs` | LSP transport, diagnostics, workspace edits, view switching |
| `src/main.rs` | CLI grammar and dispatch |

## Non-goals

Do not add new user-visible lifecycle commands in this pass.

In particular:

- no `session edit`;
- no `session refresh`—`session apply` already loads inbound-only changes when
  Markdown is unchanged;
- no automatic fallback from `edit` when LSP fails;
- no direct JSON mutation API;
- no change to grouping, sorting, Markdown syntax, or transaction semantics;
- no reimplementation of `show` through a persisted session;
- no attempt to make multi-file ICS writes truly atomic.

This should be behavior-preserving except for internal names and clearer error
contexts.

## Invariants to preserve

### Session creation

- Resolve omitted lists to every discovered list in display-name order.
- Preserve explicit list order and reject duplicates or missing lists as today.
- Resolve and persist the exact view, scope, expanded configuration, and hook
  enablement used at creation.
- Active scope stores an all-scope recovery baseline; all scope can reuse its
  rendered baseline.
- Warn on unrepresentable summary-less tasks through stderr, never stdout.
- Manual `session create` prints only the session directory to stdout.
- Live `edit` keeps ownership of the temporary session until the editor exits,
  then retains it and prints its location.

### Reconciliation and apply

- Manual apply and LSP saves must continue using the same shared engine.
- No change: preserve semantics and allow canonicalization by the manual
  adapter.
- Inbound only: accept current ICS and rerender without running hooks.
- Outgoing only: stage, hash-check, apply, verify, load accepted state, persist,
  then run `after_apply`.
- Both changed: report a conflict and modify neither Markdown nor ICS.
- Active-scope tasks completed during the session remain available for reopen.
- Source application may succeed before session refresh or hook failure; error
  context must say so accurately and transaction artifacts must remain.
- Session locking must cover the complete load/reconcile/apply/persist sequence.

### Accepted state

- Rendering an accepted state starts from the existing identity manifest so
  surviving tasks retain session IDs and new tasks receive fresh IDs.
- Baseline, recovery baseline, manifest, and accepted Markdown advance as one
  rollback-capable artifact replacement.
- Manual apply additionally replaces `tasks.md` atomically.
- LSP acceptance does not directly replace `tasks.md`; the versioned workspace
  edit remains the editor-facing transport.
- LSP in-memory baseline, recovery baseline, manifest, and accepted text update
  only after persistence succeeds.

### Close and recovery

- `session close` requires a recognized session marker and exclusive lock.
- Cleanliness remains a byte comparison of `tasks.md` and `accepted.md`.
- Dirty close refuses unless `--force` is supplied.
- Never weaken path validation or recursively remove an unrecognized directory.
- Keep transaction plans, staged files, and backups until explicit close.

## Refactor 1: unify session creation

### Existing duplication

`src/edit/live.rs::run` and `src/edit/session_commands.rs::create` both:

1. render selected lists with a resolved view;
2. report unrepresentable tasks;
3. load an all-scope recovery baseline when needed;
4. construct metadata;
5. create session artifacts.

The differences are only what happens afterward:

- live mode opens an editor and waits for LSP;
- manual mode retains immediately and prints the directory.

### Target API

Introduce one creation primitive in the edit/session layer. The exact names may
change while implementing, but the shape should resemble:

```rust
pub struct CreatedSession {
    pub session: Session,
    pub warning: Option<String>,
}

pub fn create_session(
    config: &Config,
    requested_lists: &[String],
    options: SessionOptions,
) -> Result<CreatedSession>;
```

`SessionOptions` may be the renamed current `edit::Options`; it should contain:

```rust
pub struct SessionOptions {
    pub hooks_enabled: bool,
    pub scope: Scope,
    pub view: View,
}
```

Prefer positive `hooks_enabled` internally. Keep `--no-hooks` as CLI syntax and
invert it at the boundary.

The creation primitive should own:

- `resolve_lists`;
- `render_lists_with_view`;
- recovery-baseline loading;
- metadata construction;
- `Session::create`;
- producing, but not printing, the unrepresentable warning.

The adapters should become:

```rust
// Manual
let created = create_session(...)?;
print_warning(created.warning);
println!("{}", created.session.retain().display());

// Live
let created = create_session(...)?;
print_warning(created.warning);
open_editor_and_wait_for_lsp(created.session, termination)
```

Do not bury stderr/stdout behavior inside the primitive. Returning the warning
keeps command output policy at the adapters and makes the primitive testable.

### Follow-up cleanup

Once creation is shared:

- remove `live.rs::recovery_baseline`;
- remove creation-specific repository imports from `live.rs` and
  `session_commands.rs`;
- let `edit::run` pass unresolved requested lists to the shared primitive rather
  than resolving once merely to have another layer render them;
- retain `render_lists` / `render_lists_with_view` if tests or the public crate
  API still use them; do not delete useful pure rendering helpers merely to
  reduce symbols.

## Refactor 2: centralize accepted-state rendering

### Existing duplication

Manual acceptance in `session_commands.rs::accept_state` and LSP acceptance in
`lsp.rs::accept_state` both:

1. clone the current manifest;
2. render a `TaskState` with the active view;
3. persist baseline, recovery baseline, manifest, and accepted Markdown.

The LSP path additionally:

- computes the old-document range;
- updates the in-memory `LiveDocument`;
- returns text for a workspace edit.

The manual path additionally:

- atomically replaces `tasks.md`.

### Target representation

Introduce a transport-neutral rendered acceptance value, likely in
`session_reconcile.rs` or `session.rs`:

```rust
pub struct AcceptedState {
    pub text: String,
    pub manifest: IdentityManifest,
    pub baseline: TaskState,
    pub recovery_baseline: TaskState,
}

pub fn render_accepted(
    view: &View,
    manifest: &IdentityManifest,
    baseline: TaskState,
    recovery_baseline: TaskState,
) -> Result<AcceptedState>;
```

This function should perform no filesystem or editor I/O.

### Persistence API

Replace `accept_live`, `accept_manual`, and the internal boolean
`replace_tasks` distinction with an explicit mode:

```rust
pub enum TasksUpdate {
    EditorManaged,
    ReplaceFile,
}

pub fn persist_accepted(
    root: &Path,
    accepted: &AcceptedState,
    tasks_update: TasksUpdate,
) -> Result<()>;
```

An enum is preferable to a boolean because the behavior is consequential and
call sites should read clearly.

Expected adapters:

```rust
// Manual
let accepted = render_accepted(...)?;
persist_accepted(root, &accepted, TasksUpdate::ReplaceFile)?;

// LSP
let range = full_range(&document.text);
let accepted = render_accepted(...)?;
persist_accepted(root, &accepted, TasksUpdate::EditorManaged)?;
update_live_document(document, &accepted);
return workspace_edit(range, accepted.text);
```

### Atomicity requirements

Preserve the current rollback behavior:

- prepare every replacement first;
- retain rollback copies for every artifact;
- persist replacements in a deterministic order;
- roll back prior replacements if any later replacement fails;
- include `tasks.md` in that same replacement set for manual apply.

Do not first persist accepted metadata and then write `tasks.md` separately.
That would allow a manual session to claim a baseline that its editable document
does not represent.

### Error contexts

Keep adapter-specific context around the common operation:

- inbound LSP rendering/persistence;
- outgoing source already applied but session refresh failed;
- manual source already applied but canonical document refresh failed.

The shared primitive should report the low-level operation; adapters should add
semantic consequences.

## Refactor 3: replace stale live-only names

Explicit sessions and live sessions now share one format, so these internal
names are misleading:

| Current | Target |
|---|---|
| `LIVE_FORMAT_VERSION` | `SESSION_FORMAT_VERSION` |
| `LiveMetadata` | `SessionMetadata` |
| `LoadedLiveSession` | `LoadedSession` |
| `Session::create_live` | `Session::create` |
| `load_live` | `load_from_tasks_path` or similarly precise name |
| `accept_live` / `accept_manual` | replaced by `persist_accepted` + mode |

Update all imports, tests, and error text together. Avoid compatibility aliases
unless an external crate API actually requires them; this is a pre-1.0 internal
module.

### Artifact filename decision

Do **not** rename `live.json` in this cleanup by default. Renaming it to
`session.json` would require either:

- another session format break immediately after version 3; or
- dual-read/migration logic that adds more code than the naming cleanup removes.

The Rust type can be `SessionMetadata` while the persisted filename remains
`live.json` with a short comment that the filename is retained for format
compatibility. Rename the artifact only if there is an independent reason to
bump the session format again.

Do not change the format version for symbol-only renames or refactoring that
leaves serialized fields and artifacts unchanged.

## Refactor 4: share change counts and messages

### Existing duplication

- LSP has `applied_changes_message`.
- Manual apply has `ApplyOutcome::Applied { created, updated, deleted }` plus its
  own counting and formatting.

Both inspect the same `TaskChange` sequence and produce the same words.

### Target semantic type

Add a shared value near `ChangePlan`, for example:

```rust
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct ChangeCounts {
    pub created: usize,
    pub updated: usize,
    pub deleted: usize,
}

impl ChangePlan {
    pub fn counts(&self) -> ChangeCounts;
}
```

Keep counting semantic and formatting presentational. One shared formatter can
live in the edit/session adapter layer:

```rust
pub fn applied_changes_message(counts: ChangeCounts) -> String;
```

Then:

- manual `ApplyOutcome::Applied` contains `ChangeCounts` rather than three
  fields;
- LSP uses the same counts and formatter;
- existing LSP message tests move to the shared formatter;
- add a direct count test covering create/update/delete.

The formatter should continue omitting zero-count operations and preserving the
current message:

```text
todomd: changes applied (1 created, 2 updated)
```

A successfully applied outgoing plan cannot be empty, but avoid relying on that
for unsafe indexing or malformed output.

## Refactor 5: collapse duplicate CLI selection arguments

`EditArgs` and `SessionCreateArgs` currently have the same data:

- `--no-hooks`;
- `--completed`;
- flattened view options; and
- positional lists.

Use one shared Clap `Args` type, perhaps `SessionSelectionArgs` or
`CreateArgs`, for both command variants:

```rust
Edit(SessionSelectionArgs)
SessionCommand::Create(SessionSelectionArgs)
```

It should expose one method:

```rust
impl SessionSelectionArgs {
    fn options(&self, config: &Config) -> Result<SessionOptions>;
}
```

Keep command help accurate. If sharing the direct type makes help wording too
awkward, use a flattened common struct for the identical flags and keep only the
positional-list wrapper separate. Do not accept confusing help text merely to
remove ten lines.

CLI dispatch should retain the important loading boundary:

- `session create`, `edit`, and `show` load the requested config;
- `session apply` and `session close` use persisted session metadata and do not
  require the original config path;
- `lsp` starts without loading ordinary command configuration.

## Optional cleanup: context construction

Both LSP and manual adapters construct an identical
`session_reconcile::Context` from a loaded session/document.

A safe small improvement is an associated constructor:

```rust
impl<'a> session_reconcile::Context<'a> {
    pub fn from_loaded(loaded: &'a LoadedSession) -> Self;
}
```

LSP cannot directly use `from_loaded` because its mutable `LiveDocument` is a
different type. It may still need a local constructor. Do not introduce a trait
with many getters solely to eliminate two short struct literals; that would be
abstraction soup.

A better long-term shape would be a shared semantic session-state struct owned
by both adapters, with LSP transport state wrapping it. That is beyond this
cleanup unless it falls out naturally.

## Suggested implementation order

Each step should compile and keep tests passing before continuing.

### Phase A: names and CLI data

1. Rename live-only Rust symbols while retaining the `live.json` artifact.
2. Collapse `EditArgs` / `SessionCreateArgs` where help remains clear.
3. Run rustfmt, Clippy, and CLI completion tests.

This phase is mostly mechanical and makes later APIs read correctly.

### Phase B: shared creation

1. Define `SessionOptions` with positive `hooks_enabled`.
2. Add `CreatedSession` and `create_session`.
3. Switch manual creation to it.
4. Switch live creation to it.
5. Remove duplicate recovery and metadata construction.
6. Verify stdout remains path-only for manual creation.

### Phase C: accepted-state pipeline

1. Add `AcceptedState` and pure `render_accepted`.
2. Add explicit `TasksUpdate` persistence mode.
3. Switch manual apply.
4. Switch LSP inbound and outgoing acceptance.
5. Remove old acceptance functions and booleans.
6. Exercise artifact rollback tests with both four-file and five-file sets.

### Phase D: shared result summaries

1. Add `ChangeCounts` and plan counting.
2. Move message formatting to one shared function.
3. Switch manual and LSP adapters.
4. Move/deduplicate tests.

### Phase E: documentation and dead-code pass

1. Update `DESIGN.md` only where internal architecture descriptions changed.
2. Keep `README.md` unchanged unless user-visible behavior or help text changed.
3. Search for stale names and duplicated helpers.
4. Reassess module visibility; make internals `pub(crate)` where external access
   is unnecessary, but do not break integration tests without benefit.

## Test plan

### Existing regression suite

All existing tests must remain green, especially:

- manual create/update/delete/reopen lifecycle tests;
- inbound/no-op canonicalization;
- dirty and forced close;
- manual conflict preservation;
- session lock and marker protection;
- LSP save, source watch, view switch, and fallback behavior;
- artifact replacement rollback tests;
- active/all scope repository tests;
- transaction apply and rollback tests.

### New or adjusted focused tests

Add or retain tests proving:

1. Shared creation produces byte-identical initial artifacts for manual and live
   adapters given equal options.
2. `create` returns warnings rather than printing inside the primitive.
3. Manual acceptance atomically updates `tasks.md`, `accepted.md`, manifest,
   baseline, and recovery baseline.
4. Editor-managed acceptance leaves `tasks.md` to the LSP workspace edit while
   advancing accepted artifacts.
5. Replacement failure at each artifact index restores every earlier artifact,
   including the optional `tasks.md` replacement.
6. Shared `ChangeCounts` counts every operation and shared message formatting
   omits zero entries.
7. Completion generation still includes `edit`, `session create`, `apply`,
   `close`, view flags, and `--force`.
8. `session apply` and `session close` still work when the original config path
   is absent because metadata is persisted.
9. Existing version-3 sessions remain loadable after internal symbol renames.

### Verification commands

Run from `projects/todomd`:

```console
cargo fmt --check
cargo clippy --all-targets -- -D warnings
TZ=Etc/UTC cargo test
nix build ../..#todomd --no-link
```

Use the repository's established `nix shell` wrappers when Rust tooling is not
available directly. Do not format unrelated files.

Also smoke-test help and composition:

```console
todomd session --help
todomd session create --help
session=$(todomd session create Personal)
test -f "$session/tasks.md"
todomd session apply "$session"
todomd session close "$session"
```

Use fixture calendars for destructive tests, never the operator's real vdir.

## Search checklist

Before declaring the refactor complete, these searches should either return
nothing or only intentional compatibility comments/artifact names:

```console
rg 'LiveMetadata|LoadedLiveSession|LIVE_FORMAT_VERSION|create_live' src tests
rg 'accept_live|accept_manual|replace_tasks' src tests
rg 'applied_changes_message|created.*updated.*deleted' src tests
rg 'SessionCreateArgs|EditArgs' src/main.rs
rg 'recovery_baseline\(' src/edit
```

Expected exception: literal `live.json` remains until an intentional session
format migration.

## Risks and guardrails

### Over-generalizing adapters

Manual mode writes `tasks.md`; LSP mode sends a workspace edit. Do not hide
that real difference behind callbacks, generic traits, or async abstractions.
Share semantic preparation and artifact rendering, then keep transport explicit.

### Accidental format break

Rust symbol renames do not justify changing serialized fields, filenames, or
version numbers. Verify a version-3 fixture/session still loads.

### Hook ordering

The accepted source and session state must be persisted before `after_apply`.
Hook failure reports failure but must not make an already-applied transaction
look rolled back.

### Output regressions

`session create` stdout is an API. It must contain only the path and newline.
Warnings and status belong on stderr. Do not let shared creation print directly.

### Lock lifetime

Creation needs no preexisting lock. Apply, close, and attached LSP operation must
hold the exclusive lock for their entire mutable lifetime. Refactoring session
objects must not accidentally shorten that guard's lifetime.

### Error-context loss

Generic helpers should not erase whether:

- no source writes happened;
- source writes succeeded but verification failed;
- source writes and session refresh succeeded but the hook failed.

Preserve or improve the current layered `anyhow::Context` messages.

## Definition of done

The cleanup is complete when:

- live and manual creation call one shared primitive;
- accepted-state rendering exists once;
- persistence uses an explicit editor-managed/file-replacement mode;
- stale live-only Rust names are gone, while version-3 artifacts remain
  compatible;
- change counting and applied-message formatting exist once;
- duplicate CLI selection argument definitions are removed where help remains
  clear;
- no `session edit` or `session refresh` is introduced or promised;
- all existing behavior and safety invariants remain covered;
- rustfmt, Clippy, the full test suite, and Nix build pass;
- `README.md`, `DESIGN.md`, and `ROADMAP.md` contain no stale claims created by
  the refactor.

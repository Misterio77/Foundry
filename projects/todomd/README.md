# todomd

`todomd` is a local-first CLI for editing vdir-backed VTODO lists as Markdown.
It renders selected whole lists into a temporary Markdown document, opens your
editor, previews the resulting semantic changes, and applies approved changes
back to the source `.ics` files.

`todomd` does not speak CalDAV and never invokes vdirsyncer itself. It operates
on local vdirs and offers optional lifecycle hooks for pausing and resuming
whatever synchronizes them.

```console
$ todomd                    # edit every list
$ todomd edit Postgrad      # edit chosen lists
$ todomd show               # print active tasks as JSON
```

## Status

The one-shot MVP is complete and covered by unit and CLI lifecycle tests.

It supports creating, renaming, completing, moving, and deleting **active**
tasks. Completed and cancelled VTODOs are never rendered and never touched.
Due dates, start dates, priorities, categories, and descriptions are preserved
but not yet editable; watch mode is not implemented.

See [DESIGN.md](DESIGN.md) for the full design, including the deferred
bidirectional watch driver.

## Install

With Nix:

```console
$ nix run github:Misterio77/Foundry#todomd -- edit Postgrad
```

Or from a checkout of this repository:

```console
$ nix run .#todomd -- edit Postgrad
```

## Configure

`todomd` reads `$XDG_CONFIG_HOME/todomd/config.toml`, falling back to
`~/.config/todomd/config.toml`. Override it with `--config <PATH>`.

```toml
calendar_roots = ["~/Calendars/personal"]

[hooks]
before_session = [
  "systemctl", "--user", "stop",
  "vdirsyncer.timer", "vdirsyncer.service",
]
after_apply = ["systemctl", "--user", "start", "vdirsyncer.service"]
after_session = ["systemctl", "--user", "start", "vdirsyncer.timer"]
```

`calendar_roots` are directories containing vdir collections. Each collection is
a subdirectory holding `.ics` files and a `displayname` file; the contents of
`displayname` are the list name you pass on the command line. Paths support `~`
expansion.

All hooks are optional. They are argument arrays executed directly, never shell
strings, so no quoting or word splitting is involved.

| Hook | Runs |
| --- | --- |
| `before_session` | Once, before any list is read. A failure aborts the run. |
| `after_apply` | Only after source files were successfully changed. |
| `after_session` | On every exit once `before_session` succeeded: cancellation, editor failure, conflict, apply failure, and handled `SIGINT`, `SIGTERM`, or `SIGHUP`. |

An `after_apply` failure never rolls back applied changes; it is reported as a
synchronization failure with a non-zero exit.

## Use

```console
$ todomd                     # edit every discovered list
$ todomd edit Postgrad Personal
```

A bare `todomd` edits every discovered list. Naming lists selects them and fixes
the order they are rendered in; otherwise lists are ordered by display name.
List names are not accepted at the top level, so a list called `show` stays
reachable as `todomd edit show`.

`todomd` writes a private session document and opens it with `$VISUAL`, falling
back to `$EDITOR`:

```markdown
# Postgrad

- [ ] Write paper draft <!-- todomd:id=t1 -->
- [ ] Read related work <!-- todomd:id=t3 -->

# Personal

- [ ] Buy milk, bread <!-- todomd:id=t2 -->
```

Edit it like ordinary Markdown:

- change summary text to rename a task;
- tick `- [x]` to complete a task;
- move a line under another heading to move the task between lists;
- add a `- [ ]` line without a marker to create a task;
- delete a line to delete the task.

Keep the `<!-- todomd:id=... -->` markers intact. They are session-local
identities, not VTODO UIDs, and they are how `todomd` tracks a task across a
rename or a move. Deleting a marker is treated as intentional: the old task is
deleted and a new one is created, and the preview says so.

The dialect is strict. Only the selected level-one headings and top-level
`- [ ]`/`- [x]` items are allowed, every selected list must keep its heading,
and summaries must be single-line and non-empty. Reordering tasks is ignored.

After the editor exits, `todomd` rereads the sources, reconciles, and previews
both the semantic and the filesystem changes:

```console
Postgrad:
  renamed   "Buy milk, bread" -> "Read related work"
  created   New task
  moved     Read related work <- Personal

Personal:
  renamed   "Write paper draft" -> "Submit paper"
  completed Submit paper
  moved     Submit paper <- Postgrad

Files:
  move   ~/Calendars/personal/Personal/groceries.ics -> ~/Calendars/personal/Postgrad/groceries.ics
  move   ~/Calendars/personal/Postgrad/write.ics -> ~/Calendars/personal/Personal/write.ics
  create ~/Calendars/personal/Postgrad/fa62b7c0-ac46-47dd-899c-0aa6dd3f58b6.ics

Apply these changes? [y/N]
```

Only `y` or `Y` applies the plan. Anything else, including an empty answer,
cancels it and leaves every source file untouched.

### Commands and options

| Command | Effect |
| --- | --- |
| `todomd` | Edit every discovered list. |
| `todomd edit [LISTS]...` | Edit the named lists, or every list. |
| `todomd show [LISTS]...` | Print active tasks as JSON and exit. |

| Option | Effect |
| --- | --- |
| `--config <PATH>` | Use a specific configuration file. Accepted anywhere. |
| `--no-hooks` | `edit` only. Skip every configured hook for this run. |
| `--keep` | `edit` only. Retain the session even when it was unchanged or applied cleanly. |

## Scripting

`todomd show` is the read surface for scripts and agents. It is read-only: no
session, no editor, no hooks, and no terminal required.

```console
$ todomd show Personal
[
  {
    "list": "Personal",
    "uid": "f29e1dbd-b8b4-4327-89c2-608898269a01",
    "summary": "Buy milk, bread",
    "completed": false,
    "file": "/home/gabriel/Calendars/personal/Personal/groceries.ics"
  }
]
```

Tasks are ordered by list, then by summary. `completed` is always `false` today,
because only active tasks are shown.

The `file` field matters: vdir filenames are whatever created them, so a UID
cannot be turned into a path by hand. Use `file` to read or edit an item
directly rather than searching for it.

There is no non-interactive write command. To change fields `todomd` does not
expose, edit the `.ics` at `file`, bump its `SEQUENCE`, and start your syncer.

## Safety

`todomd` treats the `.ics` files as the source of truth and the Markdown as a
disposable view of them.

- Only active tasks are rendered, so completed history cannot be disturbed.
- Sources are reread after the editor exits; if they changed underneath you,
  the run reports an inbound change or a conflict instead of applying stale
  edits.
- Before writing, every selected list is verified by identity, membership, and
  SHA-256 content hash, and each staged operation is rechecked immediately
  before it runs.
- Originals are backed up, writes go through temporary files and atomic
  rename, and a failure mid-apply triggers a hash-guarded best-effort rollback.
- Unexposed iCalendar data is preserved: patches keep `DUE`, `PRIORITY`,
  `CATEGORIES`, `DESCRIPTION`, `RELATED-TO`, `X-` properties, and nested
  components such as `VALARM`.

Because a multi-file change cannot be truly atomic, `todomd` never intentionally
applies part of a plan, but a crash mid-apply can still leave one. That is what
the retained session is for.

### Sessions

Sessions live under `$XDG_RUNTIME_DIR/todomd/`, or a private temporary
directory, and contain:

| Artifact | Contents |
| --- | --- |
| `tasks.md` | The Markdown document you edited. |
| `baseline.json` | The task state that was rendered. |
| `manifest.json` | Session ID to VTODO UID mapping. |
| `transactions/0001/` | Staged files, per-file backups, and `plan.json`. |

Sessions are retained on rejection, invalid Markdown, conflicts, and failures,
and the path is printed. They are removed after an unchanged or successful run
unless you pass `--keep`.

## Exit codes

`0` on success, including a deliberately cancelled plan. Non-zero on discovery,
hook, editor, parsing, conflict, staging, application, and post-apply failures.

## Limitations

- Active tasks only; completed and cancelled VTODOs are invisible.
- `show` reports tasks, not lists, so a list with nothing active does not appear.
- Summaries and list membership are the only editable fields.
- One primary VTODO per `.ics` file.
- No CalDAV, no watch mode, no automatic crash recovery.
- Concurrency is optimistic: `todomd` detects a source change and refuses, but
  does not lock the vdir. Use `before_session` to pause your syncer.

## Why

VTODO and CalDAV are useful synchronization formats, but existing task CLIs can
make quick, broad edits cumbersome. Markdown offers a low-friction editing
surface without becoming another persistent source of truth.

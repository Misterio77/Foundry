# todomd

`todomd` is a local-first CLI for editing vdir-backed VTODO lists as Markdown.
It turns selected whole lists into a temporary Markdown document, opens the
user's editor, previews the resulting semantic changes, and applies approved
changes back to the source `.ics` files.

The initial version does not speak CalDAV or invoke vdirsyncer directly. It
operates on local vdirs and provides optional lifecycle hooks for users who need
to pause and resume synchronization.

```console
$ todomd Postgrad Personal
```

## Status

Early implementation. `todomd` discovers configured lists, parses their active
VTODO files, creates a private session, and opens its deterministic Markdown
document in `$VISUAL` or `$EDITOR`.

After the editor exits, `todomd` strictly parses the document, rereads the source
vdirs, performs three-way reconciliation, and stages the semantic and filesystem
changes. An explicit `[y/N]` confirmation applies them with source-hash guards,
backups, atomic file replacement, and best-effort rollback. Rejected, conflicted,
and invalid sessions are retained for inspection; unchanged and successfully
applied sessions are removed.

Lifecycle hooks are not implemented yet. Until they are, pause external writers
such as vdirsyncer before applying changes.

See [DESIGN.md](DESIGN.md) for the complete design.

## Try it

Create `~/.config/todomd/config.toml`:

```toml
calendar_roots = ["~/Calendars/personal"]
```

Then run:

```console
$ nix run .#todomd -- Postgrad Personal
```

## Why

VTODO and CalDAV are useful synchronization formats, but existing task CLIs can
make quick, broad edits cumbersome. Markdown offers a low-friction editing
surface without becoming another persistent source of truth.

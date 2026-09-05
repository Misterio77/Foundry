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

Early implementation. The current read-only vertical slice discovers configured
lists, parses their active VTODO files, creates a private session, and opens its
deterministic Markdown document in `$VISUAL` or `$EDITOR`.

Source files are not modified yet. The session directory is retained after the
editor exits so its artifacts and edited Markdown can be inspected.

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

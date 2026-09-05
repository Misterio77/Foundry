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

Design-stage. See [DESIGN.md](DESIGN.md) for the proposed MVP.

## Why

VTODO and CalDAV are useful synchronization formats, but existing task CLIs can
make quick, broad edits cumbersome. Markdown offers a low-friction editing
surface without becoming another persistent source of truth.

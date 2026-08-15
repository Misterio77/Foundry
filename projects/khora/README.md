# Khora

Khora is a graphical calendar for local
[vdirs](https://vdirsyncer.pimutils.org/). It uses khal for configuration,
indexing, recurrence expansion, and iCalendar semantics; vdirsyncer remains in
charge of talking to CalDAV servers.

## Status

Khora is an early, read-only prototype. It currently provides:

- a native GTK 4/libadwaita interface;
- calendar discovery from the existing khal configuration;
- per-calendar visibility controls;
- day and week time grids with recurring and all-day events;
- a month grid with compact event previews;
- a forward-scrolling, read-only agenda; and
- explicit refreshes of khal's local index.

Event creation and editing come next. The khal dependency is isolated in
`khora.khal_adapter` so its internal API can change without leaking through the
application.

## Development

Build and run it from the Foundry root:

```sh
nix build .#khora
nix run .#khora
```

For a faster development loop, enter `projects/khora` and let direnv load its
Khora development shell, then run the source tree directly:

```sh
python -m khora
```

Khora reads the same XDG configuration and vdirs as khal. It does not configure
accounts or perform network synchronization.

## Keyboard shortcuts

- `t`: today;
- `j` / `n` and `k` / `p`: next and previous period;
- `d`, `w`, `m`, `a`: day, week, month, and agenda views;
- `r`: refresh; and
- `Ctrl`+`+`, `Ctrl`+`-`, `Ctrl`+`0`: zoom in, out, and reset.

## License

[BSD 2-Clause](LICENSE)

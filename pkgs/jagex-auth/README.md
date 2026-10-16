# jagex-auth

A small, unofficial Jagex-account authentication helper for existing RuneScape
clients. Uses your normal browser, then starts a compatible client with the
`JX_SESSION_ID`, `JX_CHARACTER_ID`, and `JX_DISPLAY_NAME` environment variables.
It does not download/update clients or fix RS3's GTK2/OpenSSL dependencies.

This project is being hardened in Foundry before standalone release. Callback
concurrency and the token-validation trust boundary are still under review;
see `.agents/2026-10-16-refactor.md`. It is not affiliated with Jagex.

## Usage

With the `rshub` desktop URL handler registered to Jagex Auth URL Handler:

```sh
jagex-auth authorize
jagex-auth launch -- runelite
jagex-auth launch -- hdos
jagex-auth launch -- runescape
```

Authorize opens your browser and prompts for a character if needed. If browser
callback delivery does not work, paste the successful-login URL into the terminal
running `authorize`. Treat that URL as a secret. Installing the desktop file does
not necessarily register it as the default handler; check your desktop's URL
associations. Do not replace an existing handler without considering its users.

`launch` never prompts or opens a browser. It requires existing credentials;
if absent or invalid it asks you to run `authorize`. An expired/revoked game
session may instead be rejected by the game: authorize again. There is no
automatic session refresh or local check that a saved session is still valid.
Arguments following the command are passed through literally. `launch` replaces
itself with the client, preserving signal and exit-status behavior.

For direct Python use (Python 3.10+ on Linux; no third-party modules):

```sh
python3 jagex-auth.py authorize
python3 jagex-auth.py launch -- runelite
```

Browser callback integration additionally requires installing an appropriate
`.desktop` handler for `jagex-auth handle-url %u`. The Nix package supplies one.

## Foundry / Nix

```sh
nix build .#jagex-auth
./result/bin/jagex-auth --help
```

Existing integration remains:

```nix
pkgs.jagex-auth.wrapLaunch pkgs.runelite
```

The returned package preserves the client's desktop files and wraps its main
executable with `jagex-auth launch -- <original-executable>`. Authentication is
runtime-only; credentials never become Nix inputs or store contents. RuneLite,
HDOS, and RS3 are Foundry integration targets; real-client smoke tests for the
refactor are pending. The helper's successful launch does not guarantee that a
particular client's runtime dependencies or account integration work.

## Storage

Credentials live in `$XDG_DATA_HOME/jagex-auth/credentials.json`, defaulting to
`~/.local/share/jagex-auth/credentials.json`. The schema has `version: 1` and the
three `JX_*` fields. The directory is private (`0700`); credential files are
created private (`0600`) and replaced atomically. Unsafe credential file types,
symlinks, files owned by another user, and group/world permissions are rejected.

Only the JSON format is supported; there is no legacy detection or migration.
Run `jagex-auth authorize` to create credentials. Do not paste credentials into
bug reports. On impermanent systems, persist the data directory if you want
sessions to survive a reboot.

Credentials are ordinary data, never shell code. They are passed to clients
through the environment, not command arguments. This is not protection from
processes running as your user (which may also read your files or environment).
Keep the account, browser profile, and machine secure. Logging out of this tool
is not yet implemented; deleting local files does not revoke a server session.

## Offline checks

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
# From the Foundry root:
nix build .#jagex-auth .#jagex-auth.passthru.tests.launch --no-link
```

Tests use synthetic credentials and temporary directories, block unexpected
network/browser calls, and exercise process launching without starting a game.
Never use real credentials in fixtures.

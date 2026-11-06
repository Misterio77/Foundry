# Stalwart checks and migration lab

Run from the repository root. These helpers use Python's standard library.
Do not run them with `python -O`, which disables assertions.

## Public checks, without sending mail

```sh
python3 -B tests/stalwart/public-check.py
python3 -B -m unittest discover -s tests/stalwart -p 'test_*.py'
```

The public check connects directly to both **public** Asterope addresses while
validating TLS for `mail.lumis.cards`; local split DNS cannot accidentally turn
its management ACL test into a tailnet request. It checks public MX/SPF,
RSA/Ed25519 DKIM and DMARC records, forward/reverse DNS, issuer metadata,
STARTTLS/implicit TLS, SMTP recipient acceptance and relay rejection, IMAP OAuth
advertisement, private API ACLs and the DAV bearer challenge. SMTP stops before
DATA: no email or forwards are generated.

An optional **0600** file can contain a raw access token or JSON with
`access_token`. Never put the token itself in a command argument or paste it
into a transcript:

```sh
python3 -B tests/stalwart/public-check.py \
  --token-file /run/user/1000/stalwart-access-token.json \
  --account contato@lumis.cards
```

This additionally tests JMAP identity, SMTP XOAUTH2, IMAP XOAUTH2/OAUTHBEARER,
read-only INBOX selection, and CalDAV/CardDAV access on both address families.
`--message-id lumis-mx-e810b205b93f-public@lumis.cards` optionally requires the
synthetic fixture's header search to work. It currently needs the staged index
fix to be activated/reindexed first. It does not fetch unrelated mail, send
messages, modify DAV, mint/refresh/revoke tokens, or validate an actual client.

The anonymous branch was exercised live; the optional bearer branch is a
reusable next-sign-in check, not evidence of a fresh AFK OAuth login. The earlier
disposable-identity browser/protocol/refresh/revocation results remain documented
in [the operational guide](../../docs/stalwart.md).

## One-off snapshot and isolated restore, Asterope 0.15.5 only

`restore-check.py` must run **as root on Asterope**, using the current native
NixOS unit and credentials. It never invokes sudo or decrypts SOPS. Copy it to a
private runtime location, e.g. `/run/stalwart-restore-check.py`, and use the Python
already in the introspection service:

```sh
python=$(systemctl show stalwart-introspection -p ExecStart --value |
  grep -o '/nix/store/[^ ]*/bin/python3' | head -1)
"$python" /run/stalwart-restore-check.py \
  --message-id lumis-mx-e810b205b93f-public@lumis.cards
```

It takes an atomic read-only Btrfs snapshot of `/persist`, copies only the mail
state into separate writable storage and starts the **same 0.15.5 binary** in a
transient systemd unit. PrivateNetwork prevents queue delivery, forwarding and
external auth calls. Bind mounts redirect `/var/lib/stalwart` to the copy;
ProtectSystem keeps other state read-only. The helper verifies both network and
DB isolation before probing. Limits are 256 MiB RAM and 25% CPU, with lower
scheduling priority. Production services are not stopped or reloaded.

Checks cover the contact/catch-all principals, active forwarding script and a
known synthetic message body. It then changes index fields and reindexes **the
copy**, proving the header-search workaround. The worker refuses to run in the
host network namespace. It reuses installed runtime credentials: this is a
crash-consistent data recovery check, **not** independent secret-key recovery.

The transient service, writable state and snapshot are removed afterward.
`--keep-snapshot` retains the read-only source **only on success** for encrypted
export; the reported snapshot includes **all of `/persist`**, not just mail.
Keep its parent root-only and delete it explicitly with `btrfs subvolume delete`
after exporting selected mail data. Remove the runtime script too. Never
`rsync`/`cp` the running RocksDB files and call that a consistent backup.

After an authorized deployment of the staged Nix field fix, rebuild existing
indexes with authenticated loopback `GET
/api/store/reindex/email/contato%40lumis.cards`, check the JSON envelope, wait for
completion and run a real-user header search. Do not use the restore worker
against the production listener.

## Pinned 1.0 lab binary

```sh
lab=$(nix build --impure --no-link --print-out-paths --expr '
  let
    flake = builtins.getFlake (toString ./.);
    pkgs = import flake.inputs.nixpkgs { system = "x86_64-linux"; };
  in pkgs.callPackage ./pkgs/stalwart-lab {}
')
"$lab/bin/stalwart" --version
```

This hash-pinned official binary is deliberately **not** exported in
`pkgs/default.nix` or selected by any service. Its version/help were checked;
there is no claim of a successful 1.0 service/OIDC migration. Verify upstream
attestation and qualify NixOS integration before production use. Never point
it at the live 0.15 DB or substitute it into the current TOML-based module.
See the [Alcyone proposal](../../docs/todo/alcyone-stalwart.md) for qualification,
identity, import, backup and rollback gates.

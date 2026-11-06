# Backups

Configuration inventory, not a current health report. Sources:
[Alcyone job](../hosts/nixos/alcyone/services/backups-jobs.nix),
[Merope repository](../hosts/nixos/merope/services/backups-repo.nix),
[snapshots](../hosts/nixos/common/optional/persist-snapshots.nix),
[PostgreSQL dumps](../hosts/nixos/common/optional/postgres.nix).

## Declared protection

- Alcyone and Merope take hourly Btrfs `/persist` snapshots, retaining at least 24 hours
  and then `7d 4w 4m`. These share the source disk's failure domain.
- Alcyone sends a read-only snapshot to `borg@merope:.` daily at 04:15, retaining
  7 daily, 4 weekly and 6 monthly archives. The repository is
  `/srv/backups/alcyone` on Merope's separate backups disk. PostgreSQL dump
  success precedes the snapshot, which precedes Borg.
- Included paths, relative to the snapshot root:

  ```text
  var/backup/postgresql        var/lib/private/authentik
  var/lib/firefly-iii          var/lib/freshrss
  var/lib/headscale            var/lib/radicale/collections
  srv/files                   srv/git                   srv/mail
  ```

- Alcyone dumps only the `authentik` PostgreSQL database. Firefly III and
  FreshRSS use SQLite in their included application directories. Raw MariaDB
  and PostgreSQL directories are not selected by Borg; explicitly include
  dumps if additional databases become important.
- Merope dumps all PostgreSQL databases locally but has **no Borg backup job**.
  Immich media (`/srv/media/photos`), its DB and media-service state therefore
  lack declared independent backups. `/persist` snapshots do not cover the
  separate media disk.
- No offsite copy, scheduled Borg integrity check, restore drill or backup-age
  alert is declared. A historical `/srv/backups/music` directory is not proof
  of an active or versioned music backup.

## Restore evidence

- **2026-09-24:** latest-archive metadata check, one Radicale calendar item and
  Headscale SQLite integrity passed. This was not full-service recovery.
- **2026-11-04:** Authentik's dump/files from Borg archive
  `alcyone-alcyone-2026-11-04T13:40:55` restored into a disconnected VM. Migration,
  server/worker and management-assisted API access worked; signing key and MFA
  records were present. Browser MFA, external clients and independently stored
  key recovery were **not tested**. The effective key came from production.

### Asterope: one-off mail recovery check

On **2026-11-07 UTC**, an atomic read-only `/persist` snapshot captured the whole
RocksDB directory, including WAL; data, blobs and search share that store. A
separate writable copy started with the original **0.15.5** binary in a verified
private network namespace and redirected state mount, capped at 256 MiB/25% CPU.
The contact/catch-all principals, active forwarding Sieve and a synthetic message
body were recovered. Header search also passed after changing fields/reindexing
**the copy**. Production services/routing were not changed, and the test unit,
writable copy and snapshot were removed.

A selected mail-state archive plus the native TOML was streamed directly through
GPG, encrypted to `7088C7421873E0DB97FF17C2245CAB70B4C225E9`, without local plaintext
staging. The independent copy is on Atlas at:

```text
~/.local/state/stalwart-backups/asterope-20261107T001312Z.tar.gpg
```

It is 2,540,369 bytes, mode 0600, with an adjacent `.json` manifest containing
its SHA-256, source closure and known recovery limitations. It contains sensitive
mail/database material, including DKIM keys and persistent configuration: retain
it encrypted. This is a manual copy on another machine, not a monitored backup
service or a second offsite archive.

**Still unproven:** GPG decryption with the operator's hardware key, recovery of
runtime credentials independently of production, and a full archive-to-fresh-host
restore. The isolated probe reused installed secrets. Rebuild the pinned NixOS
configuration, recover SOPS secrets with an independently available key, restore
the mail state with correct ownership and verify mail/DAV/signing before relying
on disaster recovery. No periodic Asterope snapshots or backup timers were added.
See [the helper's safeguards](../tests/stalwart/README.md).

## Remaining work

1. Back up Merope's irreplaceable state and Immich media/DB consistently; bulk
   movie/TV downloads can be excluded deliberately.
2. Add an offsite copy and independently recoverable Borg key/passphrase,
   Authentik key and SOPS recovery material. Do not rely on host SSH keys alone.
3. Agree Asterope mail RPO/RTO, destination, retention and key recovery, then
   implement and prove its recurring backup; the one-off copy is not automation.
4. Schedule full integrity checks, age alerts and isolated service restores.
   A snapshot is not automatically an application-consistent database backup.
   Recheck Btrfs scrub results and the music backup rather than trusting old
   capacity/corruption observations or a green timer.

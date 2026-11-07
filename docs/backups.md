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

### Asterope

There is no recurring mail backup or periodic snapshot job. A one-off **0.15.5**
data restore passed in isolation on 2026-11-07, reusing production credentials.
Its GPG-encrypted archive and manifest remain on Atlas:

```text
~/.local/state/stalwart-backups/asterope-20261107T001312Z.tar.gpg
```

That archive predates the **1.0** migration: it does not cover current mail or the
new datastore. Hardware-key decryption, independent credential recovery and a
fresh-host restore remain unproven. See the [pilot guide](stalwart.md).

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

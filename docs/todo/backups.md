# Backups

This is a plan and configuration inventory with dated spot checks, **not**
proof that all services can be recovered. The latest Borg archive passed a
metadata check; a Radicale collection item and Headscale database passed
limited scratch-restore tests. Other data and full service recovery need testing.

## Declared today

- `alcyone` takes hourly Btrfs snapshots of `/persist` via
  `hosts/nixos/common/optional/persist-snapshots.nix`. Its daily Borg job
  (`hosts/nixos/alcyone/services/backups-jobs.nix`) bind-mounts the latest
  snapshot and sends selected paths to `borg@merope:.`. The job uses a SOPS
  passphrase and SSH key, automatic repository initialization, compression, and
  retention of 7 daily, 4 weekly, and 6 monthly archives.
- `merope` exposes the receiving Borg repository at `/srv/backups/alcyone` on
  its `backups` disk (`hosts/nixos/merope/services/backups-repo.nix`). It also
  takes hourly local Btrfs snapshots of `/persist`, but **has no declared Borg
  backup job for its own data**. Snapshots on the source disk aren't an
  independent backup.
- The `alcyone` job selects `/var/lib/firefly-iii`, `/var/lib/freshrss`,
  `/var/lib/headscale`, `/var/lib/radicale/collections`, `/srv/files`,
  `/srv/git`, and `/srv/mail` from the snapshot. It does **not** include the
  persisted `/var/lib/mysql` or `/var/lib/postgresql` directories. Check which
  services use these databases before declaring the archive complete.
- There is no declared offsite backup, scheduled Borg integrity check, restore
  drill, or alert on the age of the last successful backup in this flake.
  Check separately for anything configured outside the flake.

## Live spot check (2026-09-24)

- `alcyone`: the Borg timer last fired at 04:15 -03; the job exited successfully
  at 04:16. The preceding visible runs on September 20–22 also exited
  successfully. The hourly Btrfs snapshot timer last ran successfully at 16:00,
  and 30 `persist.*` snapshot directories were visible.
- `merope`: `/srv/backups` is mounted from the dedicated Btrfs backups
  partition. `/srv/backups/alcyone` and `/srv/backups/music` exist. The former
  is owned by `borg`; the latter's existence does not establish that the music
  mirror is still being refreshed. No Borg backup timer for `merope` appeared.
- `btrfs scrub status` on the checked filesystems reported **no stats
  available**, despite printing "no errors found". This does not establish a
  completed scrub or supersede the old report of 2233 corruption errors on
  `merope`. No `btrfs-scrub*` timer appeared there.
- Using root-only Borg credentials on `alcyone`, `borg check --archives-only
  --last 1` exited successfully. The newest archive was
  `alcyone-alcyone-2026-09-24T04:15:02`. A scratch extraction of
  `run/borgbackup-alcyone-source/srv/git/.cache/nix/fetcher-cache-v1.sqlite`
  returned 20,480 bytes, matching its archived size; the temporary file was
  removed. This checks archive metadata and retrieval of one file, **not**
  repository-wide data integrity, SQLite consistency, or recovery of any
  irreplaceable application data.
- A later scratch test of the same archive restored a **non-cache Radicale
  collection item** (619 bytes) with matching `VCALENDAR` start/end lines, and
  the Headscale SQLite database (110,592 bytes, with any archived WAL/journal
  restored alongside it) returned `ok` from `PRAGMA integrity_check`. The
  first `.ics` candidate was a 152-byte file with no recognized component
  markers; restricting selection to `collection-root` and excluding cache
  directories yielded the valid item. The temporary files were removed.

The host inspection was unprivileged and read-only; the separate Borg checks
used root-only credentials without archive repair or production-file writes.
Full archive contents, other archives, passphrase recovery from an independent
location, other databases, and full application restores remain **unverified**.
Calendar framing and SQLite integrity alone do not prove the services can be
restarted from these files. The old capacity and corruption figures are
historical observations; recheck them on the hosts.

## What matters

| Data | Host | Declared protection / gap |
|------|------|---------------------------|
| Calendars and contacts | `alcyone`, Radicale | Included in the Borg job; confirm restores and retention. |
| Finance, feeds, and tailnet state | `alcyone`, Firefly III, FreshRSS, Headscale | Application directories are included; database dependencies need auditing. |
| Mail, files, and Git repositories | `alcyone` | Included in the Borg job; mail sync alone cannot undo propagated deletions. |
| Deluge state and media-service databases | `merope` | Local snapshots only; no independent backup job declared. |
| Immich media and database | `merope` | Local snapshots only; no independent backup job declared. |
| Music | `merope` | `/srv/backups/music` exists; verify whether it still runs. A mirror has no deletion history. |

Movie and TV downloads and the Prometheus TSDB can be excluded deliberately if
rebuilding or reacquiring them is acceptable. Don't back up host SSH private
keys merely to preserve access to SOPS data: verify separately that the
non-host recipient and recovery material remain available off-host.

## Database consistency

Borg reads `alcyone`'s Btrfs snapshot rather than live files, which prevents
files changing *during* the archive. A filesystem snapshot is not automatically
an application-consistent database backup. Inventory the actual Firefly III,
FreshRSS, Headscale, and Roundcube database backends and restore-test them.
`alcyone` enables both MariaDB and PostgreSQL; neither database directory is
in the selected Borg paths. If either holds data worth preserving, add a
consistent dump (or another verified recovery strategy) to the backup set.
Roundcube's PostgreSQL state may be consciously excluded if it is genuinely
rebuildable; document that decision after checking its contents.

When adding `merope`, capture Immich's PostgreSQL data consistently with its
media, and audit SQLite or other databases for Deluge, Jellyfin, Jellyseerr,
Sonarr, Radarr, Lidarr, Bazarr, Prowlarr, and other enabled services. Test a
restore rather than assuming copying a live DB or snapshot is sufficient.

## Target topology and order of work

```text
alcyone -- daily Borg --> merope /srv/backups/alcyone  [declared]
merope  -- backup ----> separate disk/repository         [missing]
critical data ----------> offsite, independent location   [missing]
```

The declared repository protects `alcyone` from loss of its own disk, but it
depends on `merope` and its backup disk. A proposed local backup of `merope`
would share that host-level failure domain. An offsite copy should cover at
least the irreplaceable data; large reacquirable downloads need not go there.
Define retention per repository and budget for the actual current sizes rather
than the old estimates.

1. **Extend the verification:** check full archive contents, repository-wide
   integrity and key/passphrase recovery from an independent location; confirm
   Btrfs scrub history and whether the music mirror still runs. Extend the
   scratch tests to a full service recovery and databases not yet covered.
2. **Close `merope`'s gap:** create an independent backup job for critical
   service state and Immich media/database. Back up from a consistent source,
   exclude replaceable bulk data, and restore-test it. A repository on another
   disk in the same host is a first step, not the offsite copy.
3. **Audit `alcyone` completeness:** account for MariaDB/PostgreSQL and any
   state not in the current path list; test database recovery. Confirm that
   six monthly archives provide enough history for delayed discoveries.
4. **Add offsite recovery:** copy or independently back up the critical set to
   another location, and keep the encryption recovery material off-host.
5. **Make failure visible:** schedule Borg integrity checks, alert when the
   latest successful backup is too old, and periodically restore files and
   databases. A green timer without a usable restore proves very little.

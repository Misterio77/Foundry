# Backups

There are none. No `restic`, `borg`, `btrbk` or anything else appears anywhere
in this flake, and sdc1 — a 932 GB disk mounted at `/srv/backups` — currently
holds 5.9 MB.

The impermanence setup makes this easier than it would otherwise be: every
`environment.persistence` entry is, by construction, an exact declaration of
what state matters. That list is the starting inventory.

## What is actually at risk

### Tier 1 — small and irreplaceable (~5 GB)

| what | where | why |
|------|-------|-----|
| firefly-iii | alcyone `/var/lib/firefly-iii` | months of shared expense tracking, hand-entered; sqlite DB and attachments both live here |
| radicale collections | alcyone `/var/lib/radicale` | calendars and contacts; khal/khard read from here |
| deluge state | merope `/var/lib/deluge` | years of seeding history on a ratio-strict tracker |
| mail | alcyone `/srv/mail/{vmail,dkim}` | ~2.4 GB; replicated to atlas and maia, so this guards against propagated deletion, not disk loss |
| git repos | alcyone `/srv/git` | cgit + git-remote |
| `*arr` + jellyfin DBs | merope `/var/lib/{sonarr,radarr,lidarr,bazarr,prowlarr,jellyfin,jellyseerr}` | rebuildable, but a very long evening |
| headscale | alcyone `/var/lib/headscale` | rebuildable, also a long evening |
| host SSH keys | `/etc/ssh/ssh_host_*` | without these, sops secrets cannot be decrypted |

Two of these are easy to overlook and rank above the `*arr` databases:

- **radicale** holds personal data with no other copy anywhere.
- **deluge state** — losing it means re-adding every torrent and rechecking
  ~92 GB, on a tracker that cares about seeding consistency.

### Tier 2 — irreplaceable, larger

| what | size | note |
|------|------|------|
| immich | 17 GB | the only category where "irreplaceable" is literal |
| music | 92 GB | private trackers; effectively unobtainable again |

### Tier 3 — do not back up

tv and movies, ~4.6 TB, re-acquirable via usenet. The Prometheus TSDB also lands
here: historically unrecoverable, but not worth the space.

### Budget

```
tier 1     ~5 GB
immich     17 GB
music      92 GB
          ------
         ~115 GB   into 932 GB
```

Roughly eight times headroom, which is comfortable for a year of restic history
with the retention below.

## The failure that hides until restore day

**Copying live database files produces backups that will not open.** Nearly
everything in tier 1 is a database, and each needs a real dump:

| engine | services | dump |
|--------|----------|------|
| sqlite | firefly, `*arr`, jellyfin, jellyseerr | `sqlite3 db ".backup out.db"` — safe while running |
| postgres | immich (merope only) | `pg_dump` |

Roundcube's postgres database is deliberately excluded: it is UI state over IMAP
and rebuilds itself. That leaves **alcyone needing no database dumps at all** —
firefly is sqlite, and everything else there is plain files.

Note also that `mysql.nix` is imported by
`hosts/nixos/alcyone/services/default.nix` while nothing on that host references
MySQL — a database server running for no one, worth removing separately.

## Replication is not backup

Mail and calendars are already replicated across atlas, maia and alcyone, and
calendars sync to every client. That covers hardware failure completely and is
why they are not urgent.

It covers nothing else. Sync faithfully propagates destruction: one bad
`mbsync`, one client deciding to resynchronise from empty, one accidental
folder deletion, and all three copies agree on the wrong answer within minutes.

So for replicated data the requirement is not redundancy but **time-separated
history**, and depth matters more than frequency — a propagated deletion may go
unnoticed for weeks. These paths are small enough that keeping a year is free.

Back up **alcyone's `/srv/mail/vmail`**, not a client's `~/Mail`. The server
store is authoritative and covers all three replicas at once; the client copies
are derived from it and one of them being stale or partially synced is exactly
the failure being protected against.

Sizing, from the client replica:

```
1.7G  personal/Archive     <- the part that matters
360M  personal/Trash
133M  personal/Sent
 18M  personal/Junk
132M  usp/Archive
 99M  usp/Sent
----
~2.4G total
```

Exclude `Junk` — it is spam, by definition worthless, and 18 MB × a year of
snapshots for nothing. `Trash` is a judgement call: keeping it buys a short
safety net for an accidental delete that has not yet been purged, at the cost of
mail you deliberately discarded persisting in backups for twelve months. That is
a privacy question more than a space one.

`services.restic.backups.<name>.backupPrepareCommand` writes dumps to a staging
directory; `backupCleanupCommand` removes them afterwards. Back up the dumps,
not the live files.

Immich additionally needs its postgres database and its media files to agree.
restic captures both in one run, so the skew is limited to the runtime of a
single backup — worst case a handful of assets referencing files that arrive in
the next snapshot, not a broken library.

## Topology

3-2-1, honestly applied:

```
alcyone ──restic over tailnet──> merope sdc1 /backups
merope  ──restic local────────>  merope sdc1 /backups
merope  ──tier 1 + immich─────>  offsite object storage  (~25 GB)
```

Backing merope up to a disk inside merope covers the common cases: accidental
deletion, a bad rebuild, sda or sdb failing. It does **not** cover fire, theft,
or the fact that all three disks hang off a single VL805 controller on one PCIe
lane. Hence offsite.

Excluding music keeps the offsite set at roughly 25 GB, which is small enough
that cost stops being a consideration. Music can be added later if desired; it
is the one irreplaceable category that is at least theoretically re-obtainable
while tracker access lasts.

## Implementation notes

`services.restic.backups.<name>` covers everything needed declaratively:
`paths`, `exclude`, `repository`, `passwordFile` (via sops), `timerConfig`,
`pruneOpts`, and the prepare/cleanup hooks. Restic encrypts client-side, so an
untrusted offsite target is fine, and deduplicates, so incrementals stay cheap.

Retention to start from:

```
--keep-daily 7 --keep-weekly 4 --keep-monthly 12
```

Monthlies are the important part, for firefly and for anything sync-replicated.
The realistic failure is not a dead disk; it is noticing in March that something
went wrong in January.

## The step that gets skipped

**A backup that has never been restored is not a backup.**

- Quarterly drill: restore firefly's database into a scratch DB and confirm a
  transaction from months ago actually reads back.
- Wire `restic check` into the schedule.
- Alert on last-successful-backup age. Prometheus and Grafana are already
  running, and a silently failing backup is worse than none — it stops you
  worrying about the thing that is no longer happening.

## Order of work

1. Local repo on sdc1, merope tier 1 only. Smallest useful thing that works.
2. Add immich and music.
3. Add alcyone over the tailnet.
4. Add the offsite target.
5. Add monitoring and the restore drill. Not optional; it is the step that turns
   the rest into a backup rather than a cron job.

Note the interaction with `merope-disk-reorganize.md`: that plan moves `/srv` to
sdb1 and remounts sdc1 at `/backups`. Paths here assume the post-migration
layout, so it is worth doing the migration first, or writing the repository path
so it survives the move.

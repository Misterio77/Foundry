# Backups

There are none. No `restic`, `borg`, `btrbk` or anything else appears anywhere
in this flake, and the 932 GB disk labelled `backups`, mounted at
`/srv/backups`, currently holds 5.9 MB.

> **Device letters are not stable on merope.** They follow USB enumeration
> order and changed on 2026-08-08 when drives were re-plugged. Always address
> disks by label (`merope`, `media`, `backups`) or UUID.

The impermanence setup makes this easier than it would otherwise be: every
`environment.persistence` entry is, by construction, an exact declaration of
what state matters. That list is the starting inventory.

## Why this stopped being theoretical

On 2026-08-08, investigating an overnight reset, three things surfaced about the
M.2 that holds every service's state:

```
[merope].corruption_errs  2233
```

1. **2233 checksum failures** logged by btrfs on the root filesystem.
2. **A scrub has never run** — `btrfs scrub status` reports "no stats
   available" against 267 GiB. So those failures were not found by verification;
   they were found *passively*, when something read those blocks and got back
   garbage. Each one returned an I/O error to whatever was reading.
3. On a single-device btrfs there is no second copy, so that data is **gone**,
   and has been for an unknown length of time.

Separately, the USB bridge in front of that disk (ASMedia ASM2362) dropped off
the bus entirely at 04:42 and needed a device reset, and on the following boot
the SuperSpeed link failed to train at all.

The counter is cumulative and undated — it may all be one bad episode from long
ago. But the honest position is that the only copy of firefly, radicale, immich
and deluge state currently lives on a disk with confirmed silent corruption,
behind a bridge with demonstrated link instability, and nobody has ever checked
whether the rest of it reads back.

**This moves ahead of `merope-disk-reorganize.md`.** A scrub is the diagnostic
that answers whether the corruption is historical or ongoing — but run it
*after* there is a copy, not before, because the answer might be "ongoing".

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
alcyone ──restic over tailnet──> merope `backups` disk, /backups
merope  ──restic local────────>  merope `backups` disk, /backups
merope  ──tier 1 + immich─────>  offsite object storage  (~25 GB)
```

Backing merope up to a disk inside merope covers the common cases: accidental
deletion, a bad rebuild, the M.2 or the media disk failing. It does **not** cover
fire, theft, or the fact that all three disks hang off a single VL805 controller
on one PCIe lane. Hence offsite.

One point in its favour: the `backups` disk reports **0 corruption errors**,
against 2233 on the M.2, and it is the only drive still on the USB 2.0 bus — so
it shares neither the SuperSpeed link nor the bridge that has been misbehaving.
480 Mbps is slow for the initial ~115 GB seed (call it two hours) and irrelevant
for incrementals.

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

Step 1 is worth doing **today**, in whatever crude form works:

```bash
restic -r /srv/backups/restic init
restic -r /srv/backups/restic backup /persist /var/lib
```

Not declarative, no dumps, no retention — and still strictly better than the
current state, which is a disk with 2233 checksum failures and no copy of
anything. Replace it with the real thing once it exists.

Note the interaction with `merope-disk-reorganize.md`: that plan moves `/srv` to
the media disk and remounts the backups disk at `/backups`. Paths here assume
the post-migration layout, so either write the repository path so it survives
the move, or accept re-pointing it once. Given the corruption findings, do not
reorder these — backups first, migration second.

# Backups

No backup system exists. No `restic`, `borg` or `btrbk` anywhere in this flake.

The only copy of anything is a plain `rsync` mirror of 92 GB of music at
`/srv/backups/music`. That covers losing the disk it came from; it has no
history and no verification, so it propagates an accidental deletion perfectly.

Motivating fact: `merope` (the M.2 holding every service's state) reports 2233
btrfs `corruption_errs` and has never been scrubbed, so those were found
passively rather than by verification. On a single-device filesystem that data
is gone.

The impermanence setup makes the inventory easy — every
`environment.persistence` entry is by construction a declaration of what state
matters.

## What is at risk

### Tier 1 — small and irreplaceable (~5 GB)

| what | where | why |
|------|-------|-----|
| radicale | alcyone `/var/lib/radicale` | calendars and contacts, no other copy anywhere |
| firefly-iii | alcyone `/var/lib/firefly-iii` | months of hand-entered expenses; sqlite + attachments |
| deluge state | merope `/var/lib/deluge` | years of seeding history on a ratio-strict tracker |
| mail | alcyone `/srv/mail/{vmail,dkim}` | ~2.4 GB; replicated, so this guards against propagated deletion |
| git repos | alcyone `/srv/git` | cgit + git-remote |
| `*arr` + jellyfin DBs | merope `/var/lib/{sonarr,radarr,lidarr,bazarr,prowlarr,jellyfin,jellyseerr}` | rebuildable, but a very long evening |
| headscale | alcyone `/var/lib/headscale` | rebuildable, also a long evening |

### Tier 2 — irreplaceable, larger

| what | size | note |
|------|------|------|
| immich | 17 GB | the only category where "irreplaceable" is literal |
| music | 92 GB | private trackers, effectively unobtainable; currently mirrored, not backed up |

### Tier 3 — deliberately excluded

tv and movies (~4 TB, re-acquirable via usenet) and the Prometheus TSDB.

**Host SSH keys**, emphatically. A host private key in a backup repository
extends that repository's blast radius to impersonating the host, and it buys
nothing: every sops creation rule lists the GPG key `7088C742…B4C225E9` as a
recipient alongside the per-host age keys, so secrets stay decryptable with no
host key at all. Rotation is `ssh-keygen`, swap the derived age key in
`.sops.yaml`, `sops updatekeys`. Nuke them from orbit and nothing is lost.

```
tier 1     ~5 GB
immich     17 GB
music      92 GB
          ------
         ~115 GB   into 932 GB
```

## Databases must be dumped, not copied

Copying live database files produces backups that will not open, and nearly all
of tier 1 is a database.

| engine | services | dump |
|--------|----------|------|
| sqlite | firefly, headscale (alcyone); `*arr`, jellyfin, jellyseerr (merope) | `sqlite3 db ".backup out.db"` — safe while running |
| postgres | immich (merope only) | `pg_dump` |

Use `backupPrepareCommand` to write dumps to a staging directory and
`backupCleanupCommand` to remove them; back up the dumps, not the live files.

Roundcube's postgres is deliberately excluded — UI state over IMAP, rebuilds
itself — so **alcyone needs no postgres dump**. It still needs sqlite dumps for
firefly and headscale; copying a live sqlite file can catch it mid-write or
miss its WAL.

Immich needs its database and media files to agree; restic captures both in one
run, so skew is bounded by a single backup's runtime.

Unrelated but adjacent: `mysql.nix` is imported by
`hosts/nixos/alcyone/services/default.nix` while nothing on that host uses
MySQL. Worth removing separately.

## Replication is not backup

Mail and calendars already replicate across atlas, maia and alcyone. That covers
hardware failure and nothing else — sync propagates destruction faithfully, and
a bad `mbsync` or an accidental folder deletion reaches all three copies within
minutes.

So for replicated data the requirement is **time-separated history**, and depth
matters more than frequency; a propagated deletion may go unnoticed for weeks.

Back up alcyone's `/srv/mail/vmail`, not a client's `~/Mail` — the server store
is authoritative and covers all three replicas at once. Exclude `Junk`. `Trash`
is a judgement call: it buys a safety net for an un-purged accidental delete, at
the cost of deliberately discarded mail persisting for a year.

## Topology

```
alcyone ──restic over tailnet──> merope `backups` disk
merope  ──restic local────────>  merope `backups` disk
merope  ──tier 1 + immich─────>  offsite object storage  (~25 GB)
```

Backing merope up to a disk inside merope covers accidental deletion, a bad
rebuild, and either disk failing. It does not cover fire, theft, or all three
disks hanging off one VL805 — hence offsite. Excluding music keeps the offsite
set around 25 GB.

The `backups` disk reports 0 corruption errors and is the only drive still on
USB 2.0, so it shares neither the SuperSpeed link nor the bridge in front of the
M.2. 480 Mbps is slow for the initial seed and irrelevant for incrementals.

## Retention

```
--keep-daily 7 --keep-weekly 4 --keep-monthly 12
```

Monthlies are the important part. The realistic failure is not a dead disk; it
is noticing in March that something went wrong in January.

## A backup that has never been restored is not a backup

- Quarterly drill: restore firefly's database into a scratch DB and confirm a
  transaction from months ago reads back.
- Wire `restic check` into the schedule.
- Alert on last-successful-backup age. A silently failing backup is worse than
  none, because it stops you worrying about the thing that is not happening.

## Order of work

1. Local repo on the `backups` disk, merope tier 1 only.
2. Add immich and music.
3. Add alcyone over the tailnet.
4. Add the offsite target.
5. Add monitoring and the restore drill — the step that turns the rest into a
   backup rather than a cron job.

Step 1 is worth doing today in whatever crude form works:

```bash
head -c 32 /dev/urandom | base64 > /root/.restic-pass && chmod 600 /root/.restic-pass
cat /root/.restic-pass          # store off-machine BEFORE init
export RESTIC_PASSWORD_FILE=/root/.restic-pass

restic -r /srv/backups/restic init
restic -r /srv/backups/restic backup /persist /var/lib \
  --exclude '/var/lib/jellyfin/transcodes'
```

> **The password is the whole backup.** If it only exists on the M.2 and the M.2
> is what dies, the repository is a very well-encrypted brick.

## Interaction with `merope-disk-reorganize.md`

That plan moves `/srv` to the media disk and remounts `backups` at `/backups`,
so either choose a repository path that survives the move or accept re-pointing
it once.

Do backups first. Once restic covers music, delete the 92 GB `rsync` mirror
rather than letting it drift.

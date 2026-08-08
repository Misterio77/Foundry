# merope disk reorganization

Consolidate all media onto sdb in one btrfs subvolume so every import becomes a
rename or hardlink instead of a cross-device copy, and sda — which holds the
swapfile — sees no media I/O at all.

## Background

On 2026-08-07 merope hung for ~48 minutes under a single 1.1 GB movie import.
No OOM, no panic, no thermal event: `/swap/swapfile` shares sda with the rootfs,
and a Radarr cross-device import saturated that disk at ~85 MiB/s, so page-ins
queued behind bulk I/O indefinitely.

That was mitigated in `e5ae4001` (watchdog, ondemand governor, swappiness, PSI)
and `e5e1048a` (cgroup weights, BFQ), which turned the failure from a hang into
graceful degradation. This document removes the underlying cause.

Measured during a four-season download the same evening:

| device | queue depth | throughput | note                          |
|--------|-------------|------------|-------------------------------|
| sda    | ~3          | 70–82 MiB/s| SSD, coping                   |
| sdb    | 20–29       | ~28 MiB/s  | 95% utilised, seek-bound      |

Network ingest was only 26 MiB/s. Every byte moved roughly three times: written
to sda, read back off sda for the import, written to sdb — and both disks share
a single VL805 controller on one PCIe lane.

## Target layout

```
sda2  ephemeral root + /persist (service state) + swapfile
sdb1  subvolume "srv" -> /srv
      ├── media/{tv,movies,photos,music}
      ├── torrents/{downloading,completed}
      └── incoming/{downloading,complete}   <- sabnzbd
sdc1  -> /backups
```

Every app-visible path is unchanged: `/srv/media/tv`, `/srv/media/music`,
`/srv/torrents/completed`. Deluge, Lidarr, Sonarr, Radarr, Bazarr, Immich and
Jellyfin need no reconfiguration — only the device underneath changes. Deluge in
particular stores an absolute save path per torrent, so path stability is what
avoids re-adding and rechecking every torrent.

Only SABnzbd's two directories move, and it keeps no per-item path history.

## Prep

Safe to do at any time, before the maintenance window.

1. Confirm the Sonarr/Radarr queues are empty; nothing mid-import.
2. Remove video torrents through deluge ("remove torrent and delete data"), not
   `rm`, so deluge's state stays consistent. Their library copies on sdb are
   independent inodes — those imports were cross-device copies — so this cannot
   touch them. Shrinks the migration payload and frees space on sda.
3. Measure, and check for existing inode flags, since neither `cp` nor `rsync`
   carries them:

   ```bash
   du -sh /srv/media/music /srv/torrents
   lsattr -d /mnt/{tv,movies,photos} /srv/media/music /srv/torrents /srv/torrents/*
   ```

## Migration

### 1. Stop the media stack

```bash
systemctl stop \
  deluged delugeweb sabnzbd \
  sonarr radarr lidarr bazarr prowlarr \
  jellyfin jellysearch \
  immich-server immich-machine-learning

systemctl is-active <same list>   # verify, do not assume
```

Two distinct reasons, same list. The `*arr`s, bazarr, deluge, sabnzbd and immich
**write** into the tree and would leave the copy inconsistent — immich most
dangerously, since its database stays on sda and would end up referencing a
photo that never made it across. Jellyfin and jellysearch are read-only here
(jellyfin's metadata lives in `/var/lib/jellyfin`) but hold **open file
handles**, which block the unmounts below.

Leave `postgresql`, `redis-immich` and `meilisearch` running — all on sda, none
touch `/srv`, and immich returns without a database restart.

### 2. Back music up to sdc1

92 GB onto a 932 GB disk currently holding 5.9 MB. Makes the whole migration
reversible.

### 3. Build the new subvolume (reflink — no data moves)

```bash
mount -o subvolid=5 /dev/sdb1 /mnt        # fs root, not the default subvol
btrfs subvolume create /mnt/srv
mkdir -p /mnt/srv/media
cp -a --reflink=always /mnt/{tv,movies,photos} /mnt/srv/media/
```

Run as root, or `cp -a` silently drops ownership. `--reflink=always` errors out
rather than falling back to a real 4.6 TB copy.

Verify immediately — a silent deep copy looks exactly like success:

```bash
btrfs filesystem usage /mnt                        # free space should barely move
du -sh --apparent-size /mnt/tv /mnt/srv/media/tv   # should match
```

Expect minutes to an hour of metadata work, but no data movement and no bus
traffic.

### 4. Migrate music and torrents (the one slow step)

Unmount the sdb subvolumes from `/srv` first. Leave them mounted and rsync
descends into them and hauls 4.6 TB back across the bus into the subvolume that
already holds it via reflink:

```bash
umount /srv/media/tv /srv/media/movies /srv/media/photos

rsync -aHAX -x --info=progress2 \
  /srv/media /srv/torrents \
  /mnt/srv/
```

Both trees in a **single** invocation. `-H` only preserves links within one
transfer set, so separate runs turn every hardlinked music pair into two files
and 92 GB into 184.

`-x` is a second line of defence, but note each btrfs subvolume reports a
distinct `st_dev`, so it stops at subvolume boundaries as well as filesystem
ones. The unmount is the real guard.

### 5. Verify before deleting anything

```bash
find /mnt/srv -links +1 | wc -l   # must match the source count
```

### 6. Repoint mounts

Subvolume `srv` mounts directly at `/srv` — no bind mount and no `/persist/srv`,
since nothing about sdb is ephemeral. sdc1 moves to `/backups`.

Before unmounting the old `/srv`:

```bash
fuser -vm /srv     # must be empty
```

If something still holds it the unmount fails, and reaching for a lazy unmount
leaves processes quietly reading the old sda inodes while appearing to have
migrated. That is how the source gets deleted in step 8 with data still in use.

### 7. Remove dead config and restart

Delete the `environment.persistence` entries and disko mountpoints for
`/srv/media/{tv,movies,photos}` — stale persistence entries quietly resurrect
directory structures that were meant to be gone.

Create the sabnzbd directories. Rebuild, start services, and confirm deluge
shows everything seeding. Fast-resume should hold since `rsync -a` preserves
mtime, avoiding 92 GB of software SHA-1 on an A72 without crypto extensions.

### 8. Clean up last

```bash
btrfs subvolume delete /mnt/{tv,movies,photos}   # old sdb subvolumes
# then the old /srv contents on sda2
```

## Config changes

```nix
# sabnzbd.nix — both on sdb, so the final move is a rename
download_dir = /srv/incoming/downloading
complete_dir = /srv/incoming/complete
```

Keeping `download_dir` on sda would reintroduce the burst: SABnzbd unpacks in
`download_dir` and then *moves* to `complete_dir`, which across filesystems is a
full-size copy.

```nix
# deluge.nix — spinning disk now
max_active_downloading = 3;     # was 8
max_connections_global = 200;   # was -1
```

Eight concurrent torrents was survivable on flash and is a seek generator on
rust. Also in SABnzbd: enable pause-downloading-during-post-processing, and cut
usenet connections from 225 to ~50 — a Pi 4 cannot use anywhere near that, and
each is a TLS socket with its own buffers and softirq cost.

## Deliberately not doing: `chattr +C`

`+C` disables data checksums as well as COW, and both hardlinks (torrents) and
renames (usenet) carry the flag into the library — so the entire collection
would end up without `btrfs scrub` bitrot detection. On a single-device
filesystem corruption is not repairable anyway, but it is still worth detecting.

The fragmentation `+C` prevents is mostly a *torrent* problem, from out-of-order
piece writes; usenet writes sequentially. Measure with `filefrag` on a few
imported files after the migration and only revisit if it is genuinely bad.

## Rollback

Nothing is deleted until step 8, music is backed up on sdc1, and reverting is a
disko change plus a generation switch.

## Verify afterwards

- `stat` a freshly imported episode in both staging and library: same inode,
  link count 2. If it is still copying, that shows up immediately rather than in
  three weeks.
- Watch `qd_sdb` during the next import. The 26–29 spikes should stop existing.

## Known trade

`tv`, `movies` and `photos` stop being subvolumes and become plain directories,
so per-library btrfs snapshots are no longer possible — `srv` would be
snapshotted as a whole. Nothing snapshots them today.

# merope disk reorganization

Consolidate all media onto the **media** disk in one btrfs subvolume, so every
import is a rename or hardlink instead of a cross-device copy, and the M.2 —
which holds the swapfile — sees no media I/O.

## Disks

Kernel letters are not stable here; they follow USB enumeration order and have
changed repeatedly. Address disks by label or UUID.

| label     | size   | allocated | role                          |
|-----------|--------|-----------|-------------------------------|
| `merope`  | 465 GB | 250 GiB   | M.2, root + `/persist` + swap |
| `media`   | 12 TB  | 4.03 TiB  | tv, movies, photos            |
| `backups` | 932 GB | 92 GiB    | backup target (music mirror)  |

Both `merope` and `media` are on USB 3 behind one VL805 / PCIe Gen2 x1 lane:
212 and 197 MB/s alone, 165 and 170 concurrent, ~335 MB/s combined. Separate
request queues on a shared path — which is what matters, since the failure this
fixes was swap page-ins queued behind bulk writes on one device, not bandwidth.

## Prerequisites

- [ ] **Scrub `merope`** — 250 GiB, ~25 min. It reports 2233 `corruption_errs`
      and has never been scrubbed.
- [ ] **Scrub `media`** — 4.03 TiB, ~9–10 h. 4 TB should not be reflinked into a
      new subvolume on the assumption it is intact.

```bash
btrfs scrub start -c 3 /      # -c 3 = idle I/O class; root required
btrfs scrub status /
```

Neither filesystem is redundant, so a scrub reports rather than repairs. The
line that matters is `csum errors`: zero means the 2233 are historical, non-zero
means it is ongoing and `dmesg` names the files.

It runs in kernel threads, so it outlives the SSH session that started it. An
unmount cancels it, but progress is saved — `btrfs scrub resume <mountpoint>`
continues, while `start` begins again from zero. It is also cancellable at any
time, which makes it cheap to abort if it is in the way.

Cost, measured on the M.2 at 176 MiB/s with services running: `io some avg10`
around 14 and load ~2.3, with playback unaffected. On the HDD the cost is seek
latency rather than bandwidth; streaming absorbs it, concurrent unpacking or
imports will not.

After a clean scrub, zero the counter so it becomes a dated baseline instead of
an ever-growing mystery:

```bash
btrfs device stats -z /
```

## Target layout

```
merope   ephemeral root + /persist (service state) + swapfile
media    subvolume "srv" -> /srv
         ├── media/{tv,movies,photos,music}
         ├── torrents/{downloading,completed}
         └── incoming/{downloading,complete}   <- sabnzbd
backups  -> /backups
```

Every app-visible path is unchanged, so deluge, the `*arr`s, bazarr, immich and
jellyfin need no reconfiguration — only the device underneath moves. Deluge
stores an absolute save path per torrent, so path stability is what avoids
re-adding and rechecking everything. Only SABnzbd's two directories move, and it
keeps no per-item path history.

## Before the window

No downtime; all of this can be done in advance.

1. **Confirm the `merope` scrub finished clean**, then zero the counter so it
   becomes a dated baseline instead of a cumulative mystery:

   ```bash
   btrfs scrub status /
   btrfs device stats -z /
   ```

2. **Write the config changes** (see "Config changes" below) so the rebuild
   inside the window is one step: the disko `srv` subvolume and the `/backups`
   move, the removed `environment.persistence` entries and disko mountpoints for
   `/srv/media/{tv,movies,photos}`, and the sabnzbd and deluge settings.

3. Confirm the Sonarr/Radarr queues are empty; nothing mid-import.
4. Remove finished video torrents through deluge ("remove torrent and delete
   data"), not `rm`, so its state stays consistent. Library copies on `media` are
   separate inodes, so this cannot touch them. Shrinks the payload.
5. Check for inode flags, which neither `cp` nor `rsync` carries:

   ```bash
   lsattr -d /mnt/{tv,movies,photos} /srv/media/music /srv/torrents /srv/torrents/*
   ```

6. Re-measure with a btrfs-aware tool. `du` and `find -links` are both blind to
   reflinks — reflinked files are separate inodes with `nlink=1`, and `du`
   counts each one's blocks in full:

   ```bash
   btrfs filesystem du -s /srv/media/music /srv/torrents
   ```

   `Exclusive` plus one copy of `Set shared` is what the data actually costs
   today; `Total` is what it will cost after the move.

## The window

Roughly an hour with the media stack down, most of it step 3.

### 1. Stop the media stack

```bash
systemctl stop \
  deluged delugeweb sabnzbd \
  sonarr radarr lidarr bazarr prowlarr \
  jellyfin jellysearch \
  immich-server immich-machine-learning

systemctl is-active <same list>    # verify, do not assume
```

The `*arr`s, bazarr, deluge, sabnzbd and immich **write** into the tree — immich
most dangerously, since its database stays on `merope` and would end up
referencing a photo that never made it across. Jellyfin and jellysearch are
read-only but hold **open handles**, which block the unmounts below.

Leave `postgresql`, `redis-immich` and `meilisearch` running: all on `merope`,
none touch `/srv`, and immich returns without a database restart.

### 2. Build the new subvolume — minutes, no data moves

```bash
mount -o subvolid=5 /dev/disk/by-label/media /mnt   # fs root, not default subvol
btrfs subvolume create /mnt/srv
mkdir -p /mnt/srv/media
cp -a --reflink=always /mnt/{tv,movies,photos} /mnt/srv/media/
```

Root, or `cp -a` silently drops ownership. `--reflink=always` errors out rather
than falling back to a real 4 TB copy. Verify immediately — a silent deep copy
looks exactly like success:

```bash
btrfs filesystem usage /mnt                        # free space should barely move
du -sh --apparent-size /mnt/tv /mnt/srv/media/tv   # should match
```

### 3. Migrate music and torrents — ~20–30 min, ~170 GiB

```bash
umount /srv/media/tv /srv/media/movies /srv/media/photos

rsync -aHAX -x --info=progress2 \
  /srv/media /srv/torrents \
  /mnt/srv/
```

**Unmount first**, or rsync descends into the `media` subvolumes and hauls 4 TB
back across the bus into the subvolume that already holds it via reflink.

**Both trees in one invocation**, so `-H` sees them together — it only preserves
links within a single transfer set. Only 17 files in `/srv/torrents` are actually
hardlinked, so this is cheap insurance rather than a crisis averted.

#### Expect this to grow by ~46 GiB

Music and torrents currently **share ~46 GiB of extents via reflink**, because
Lidarr imported from the torrent data on the same filesystem:

| | total | exclusive | shared |
|---|---|---|---|
| `/srv/media/music` | 92.75 GiB | 46.85 GiB | 45.75 GiB |
| `/srv/torrents`    | 77.50 GiB | 31.49 GiB | 45.99 GiB |

Reflinks cannot cross filesystems, so this copy destroys that sharing no matter
which tool is used — there is no rsync or `cp` flag that preserves it across
devices. Both trees occupy ~124 GiB on `merope` today and will occupy ~170 GiB
on `media` afterwards.

That is 0.7% of free space, so it is affordable — but it is worth reclaiming,
because the sharing is whole-file rather than scattered. Measured over 150
random music files, the distribution is strictly bimodal:

| share ratio | files | meaning |
|---|---|---|
| 0%       | 69% | no counterpart in the current seeding set |
| 1–89%    | 0%  | nothing partial — no file is fragmentarily shared |
| 90–99%   | 23% | clone plus a rewritten tag block, ~115 KiB of a 25.7 MiB file |
| 100%     |  8% | pure clone, byte-identical |

Lidarr reflink-imports from the torrent and then rewrites tags, so the audio
extents stay shared while only the metadata block (tags plus embedded art)
diverges. Because that divergence is 0.45% of a file rather than scattered
through it, block-level dedupe recovers essentially all of the 46 GiB.

The unshared majority is not stale. Of 426 seeded album payloads, **87% of FLAC
releases are reflinked into the library and 2% of MP3 releases are** — the MP3
torrents are seeded for ratio and never imported, since the library keeps
lossless. So both sides carry a large exclusive share by design:

```
torrents  77.5 GiB = 46.0 shared (FLAC, imported) + 31.5 excl (MP3, ratio only)
music    92.75 GiB = 45.8 shared (from those)     + 46.9 excl (predates/outside seeds)
```

Both trees must migrate whole. Neither exclusive portion is redundant.

**Re-dedupe after the migration** to restore it:

```bash
duperemove -rdh /srv/media/music /srv/torrents
```

Future imports reflink on their own again, since both trees land on the same
filesystem — which is the point of the migration. Only the copied-across history
needs the one-off pass.

> **Do not run a file-level duplicate remover here.** `rmlint` and friends
> compare content, not extents, so they report ~8.65 GB of "removable
> duplicates" that are already shared and would free nothing — while deleting
> the torrent-side copies and destroying 564 seeds. Dedupe, never delete.

### 4. Verify before deleting anything

```bash
find /mnt/srv -links +1 | wc -l    # must match the source count
```

### 5. Repoint mounts

Subvolume `srv` mounts directly at `/srv` — no bind mount, no `/persist/srv`.
The backups disk moves to `/backups`.

```bash
fuser -vm /srv     # must be empty before unmounting
```

Never resort to a lazy unmount: processes keep reading the old inodes while
appearing to have migrated, and step 7 then deletes data still in use.

### 6. Remove dead config and restart

Delete the `environment.persistence` entries and disko mountpoints for
`/srv/media/{tv,movies,photos}` — stale persistence entries quietly resurrect
directory structures meant to be gone. Create the sabnzbd directories, rebuild,
start services, confirm deluge shows everything seeding. Fast-resume should hold,
since `rsync -a` preserves mtime — otherwise it is 92 GB of software SHA-1 on an
A72 without crypto extensions.

## After it is proven

Only once deluge is seeding, Jellyfin plays and immich resolves its library:

```bash
btrfs subvolume delete /mnt/{tv,movies,photos}
# then the old /srv contents on `merope`
```

## Config changes

```nix
# sabnzbd.nix — both on the media disk, so the final move is a rename
download_dir = /srv/incoming/downloading
complete_dir = /srv/incoming/complete
```

Split across filesystems, SABnzbd's move from `download_dir` to `complete_dir`
becomes a full-size copy.

```nix
# deluge.nix — spinning disk now
max_active_downloading = 3;     # was 8
max_connections_global = 200;   # was -1
```

This is about *seeks*, not bandwidth. Also in SABnzbd: enable
pause-during-post-processing and cut usenet connections from 225 to ~50 — even at
1.8 GHz a Pi 4 cannot use anywhere near that, and each is a TLS socket with its
own buffers and softirq cost.

## Decisions

**No `chattr +C`.** It disables checksums as well as COW, and both hardlinks and
renames carry the flag into the library, so the whole collection would lose
bitrot detection. The fragmentation it prevents is mostly a torrent problem;
usenet writes sequentially. Measure with `filefrag` afterwards and revisit only
if it is genuinely bad.

**`tv`, `movies` and `photos` become plain directories**, so per-library
snapshots are no longer possible — `srv` would be snapshotted whole. Nothing
snapshots them today.

## Rollback

Nothing is deleted until step 7, music is mirrored on `backups`, and reverting is
a disko change plus a generation switch.

## Verify afterwards

`stat` a freshly imported episode in staging and library: same inode, link
count 2. If it is still copying, that shows up immediately rather than in three
weeks.

# merope disk reorganization

Consolidate all media onto the **media** disk in one btrfs subvolume so every
import becomes a rename or hardlink instead of a cross-device copy, and the M.2
— which holds the swapfile — sees no media I/O at all.

## Device naming: use labels, never letters

Kernel device letters on this host are **not stable**. They are assigned in USB
enumeration order, which changes when a drive is re-plugged, moved between
ports, or hot-plugged after boot. On 2026-08-08 the 12 TB and the 932 GB swapped
letters simply by being plugged in a different order.

| label      | size   | role                    | filesystem UUID prefix |
|------------|--------|-------------------------|------------------------|
| `merope`   | 465 GB | M.2 NVMe, root + swap   | `1660ec93`             |
| `media`    | 12 TB  | tv, movies, photos      | `b8126efa`             |
| `backups`  | 932 GB | backup target           | `6d8471ca`             |

Everything below refers to these labels. Use `/dev/disk/by-label/<label>` or
`/dev/disk/by-uuid/` in commands. Any instruction naming `sdb` or `sdc` is a bug.

## Background

On 2026-08-07 merope hung for ~48 minutes under a single 1.1 GB movie import.
No OOM, no panic, no thermal event: `/swap/swapfile` shares the M.2 with the
rootfs, and a Radarr cross-device import saturated that disk, so page-ins queued
behind bulk I/O indefinitely.

That was mitigated in `e5ae4001` (watchdog, ondemand governor, swappiness, PSI)
and `e5e1048a` (cgroup weights, BFQ), which turned the failure from a hang into
graceful degradation.

### What 2026-08-08 changed

At 04:42 the host reset again, and the cause was **not** swap. The USB bridge
backing the M.2 (ASMedia ASM2362, `174c:2362`) stopped answering SCSI commands:

```
sda uas_eh_abort_handler ... inflight: CMD OUT
scsi host0: uas_eh_device_reset_handler start
usb 2-2: reset SuperSpeed USB device number 2
```

Swap sat flat at 2.27 GiB throughout and 4.4 GiB stayed available — memory was
never involved. The watchdog from `e5ae4001` caught it: **105 seconds of
downtime, self-recovered**, against 48 minutes and a manual power cycle the day
before.

On the reboot that followed, the SuperSpeed link failed to train
(`usb2-port2: Cannot enable. Maybe the USB cable is bad?`) and all three drives
enumerated on the USB 2.0 bus at 480 Mbps. A cold power cycle — full power
removal, not a reboot — restored it.

### The 28 MiB/s figure was wrong

Measured during a four-season download on 2026-08-07:

| device | queue depth | throughput  | note                     |
|--------|-------------|-------------|--------------------------|
| M.2    | ~3          | 70–82 MiB/s | SuperSpeed, coping       |
| media  | 20–29       | ~28 MiB/s   | 95% utilised             |

That was read as a seek-bound spinning disk. It was not. The 12 TB was plugged
into a **USB 2.0 port**, and 28 MiB/s is a saturated 480 Mbps link. On USB 3,
measured 2026-08-09 with the boot problems resolved:

```
1258291200 bytes (1.3 GB) copied, 6.88015 s, 183 MB/s
```

**6.5× faster**, and the drive was never the constraint. Every capacity argument
in this document was originally sized against the wrong number; the migration is
now clearly worth doing rather than a careful trade.

### New caveat: shared PCIe lane

With the media disk on USB 3, it and the M.2 both sit on the SuperSpeed side of
the VL805 — one PCIe Gen2 x1 lane, roughly 440 MB/s usable **shared**. Before,
the M.2 had that lane to itself. This is still vastly better than 40 MB/s, but
the premise is *separate spindles, shared path*, not fully independent I/O.

### Boot order — resolved 2026-08-09

Putting the media disk in USB 3 broke booting, in two separate stages. Both are
fixed; both live in firmware, outside this flake, so they survive a reinstall
and will not reappear in a `nixos-rebuild`.

**Stage 1 — the EEPROM bootloader.** It walks USB devices in port order and, on
finding no bootable partition on the drive in 2-1, falls through to the SD slot
and then loops (the default `BOOT_ORDER` ends in `f`). Fixed by excluding the two
data drives by VID:PID so it never considers them:

```
USB_MSD_EXCLUDE_VID_PID=174c:55aa,152d:0580
```

Applied by rebuilding the EEPROM image with `rpi-eeprom-config --config`, then
copying it to `/firmware/pieeprom.upd` with a matching `pieeprom.sig` from
`rpi-eeprom-digest`. Note `--apply` does **not** work on NixOS: the nixpkgs
wrapper points `FIRMWARE_ROOT` at a directory that does not exist.

**Stage 2 — U-Boot.** The EEPROM then handed off cleanly, but U-Boot failed the
same way for a different reason. The installed binary was **U-Boot 2021.04**,
which predates `bootstd` and uses legacy `distro_bootcmd`. There, `rpi.h`
declares USB as a single instance:

```c
#define BOOT_TARGET_USB(func) func(USB, usb, 0)
```

so `boot_targets` contains exactly one `usb0`, and `usb_boot` only ever tries
`devnum=0`. With the media disk in 2-1 it enumerated first, had no
`extlinux.conf`, and U-Boot moved on to `mmc0`/`pxe`/`dhcp` without ever looking
at the M.2.

Fixed by replacing `/firmware/u-boot-rpi4.bin` with a current build
(`nixpkgs#ubootRaspberryPi4_64bit`, U-Boot 2026.04), which uses `bootstd` and
enumerates every bootdev rather than a single hardcoded index. The 2021.04
binary is kept beside it as `u-boot-rpi4.bin.bak`.

> **Recovery note.** `/firmware` is on the M.2 *inside* the Argon case. If a
> future U-Boot or EEPROM change fails to boot, recovery means opening the case
> and mounting that partition elsewhere — there is no SD card in the slot. Keep
> a copy of `u-boot-rpi4.bin.bak` off-machine before touching either again.

Result: both drives negotiate 5000 Mbps and the host boots unattended, so the
watchdog is safe again.

## Target layout

```
merope   ephemeral root + /persist (service state) + swapfile
media    subvolume "srv" -> /srv
         ├── media/{tv,movies,photos,music}
         ├── torrents/{downloading,completed}
         └── incoming/{downloading,complete}   <- sabnzbd
backups  -> /backups
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

### 2. Back music up to the backups disk

92 GB onto a 932 GB disk currently holding 5.9 MB. Makes the whole migration
reversible.

### 3. Build the new subvolume (reflink — no data moves)

```bash
mount -o subvolid=5 /dev/disk/by-label/media /mnt   # fs root, not the default subvol
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
since nothing about the media disk is ephemeral. The backups disk moves to
`/backups`.

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
# sabnzbd.nix — both on the media disk, so the final move is a rename
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
rust. Note this is about *seeks*, not bandwidth — at 175 MB/s the link is no
longer the limit, but random access on a 12 TB drive still is. Also in SABnzbd: enable pause-downloading-during-post-processing, and cut
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

Nothing is deleted until step 8, music is backed up on the backups disk, and
reverting is a disko change plus a generation switch.

## Verify afterwards

- `stat` a freshly imported episode in both staging and library: same inode,
  link count 2. If it is still copying, that shows up immediately rather than in
  three weeks.
- Watch queue depth on the media disk during the next import. The 26–29 spikes
  should stop existing — though note they were largely a USB 2.0 artifact and
  may already be gone before any of this work happens.

## Prerequisites

- [x] **The host boots unattended** with both drives on USB 3 — EEPROM exclusion
      plus U-Boot 2026.04, done 2026-08-09.
- [x] **Music is copied off the M.2** — 92 GB to the `backups` disk, verified.
      That was the only irreplaceable data on the disk with 2233 checksum
      failures; everything else there is regenerable service state.
- [ ] **A scrub has run** on both the M.2 and the media disk. 4.6 TB should not
      be reflinked into a new subvolume on the assumption it is intact, and the
      2233 errors on the M.2 are still unexplained — cumulative, undated, and
      never verified. At 183 MB/s this is now affordable.

## Known trade

`tv`, `movies` and `photos` stop being subvolumes and become plain directories,
so per-library btrfs snapshots are no longer possible — `srv` would be
snapshotted as a whole. Nothing snapshots them today.

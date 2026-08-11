# Hardening after the 2026-08-07 stall.
#
# merope hung for ~48min with all four cores pinned: no OOM, no panic, no
# thermal event (56C throughout). /swap/swapfile lives on sda, the same USB
# SSD as the rootfs, and swappiness=60 had ratcheted ~4.2G of cold anonymous
# pages onto it over days. A torrent write plus a Radarr cross-disk import
# saturated that device at ~85MiB/s, so page-ins queued behind bulk I/O
# indefinitely. Nothing exceeded a memory limit, so the OOM killer never fired
# and the box never crashed -- it just stopped, until it was power cycled.
{lib, ...}: {
  # The BCM2835 watchdog caps at 15s in hardware; systemd pings at half the
  # timeout. PID 1 failing to get scheduled for 15s means the machine is
  # already unrecoverable, so this trades a silent multi-hour hang for a
  # reboot. It does not fix any root cause -- it bounds the blast radius of
  # whatever the next unknown failure turns out to be.
  systemd.settings.Manager.RuntimeWatchdogSec = "15s";

  boot = {
    # CONFIG_PSI=y but CONFIG_PSI_DEFAULT_DISABLED=y on this kernel, so
    # /proc/pressure does not exist without this flag. During the incident the
    # kernel was not even measuring stall time.
    kernelParams = ["psi=1"];

    # Overrides common/global/swappiness.nix (60). MemAvailable never dropped
    # below 3.6G during the incident and AnonPages sits at ~2.5G of 7.8G, so
    # swap here is not load-bearing -- it was opportunistic eviction of cold
    # pages onto the one device that was already saturated. Committed_AS does
    # exceed RAM, so keep the swapfile as a backstop; just stop it being a habit.
    kernel.sysctl."vm.swappiness" = lib.mkForce 10;
  };

  # The media units carry a lowered IOWeight, which mq-deadline (the default
  # here) ignores outright -- it has no notion of I/O weights or priorities at
  # all. BFQ is the only scheduler on this kernel that honours them, and it is
  # what actually lets system and interactive I/O preempt a bulk import on the
  # shared USB bus. Without this rule that half of the tuning is decoration.
  boot.kernelModules = ["bfq"];
  services.udev.extraRules = ''
    ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="bfq"
  '';

  # Userspace last resort, replacing earlyoom after the 2026-08-11 swap
  # exhaustion. earlyoom only acts when available memory AND free swap are both
  # under their thresholds: swap crossed 5% at 02:14 but RAM did not until
  # 06:10, so it watched the swapfile drain to zero for four hours. It then sent
  # 88 SIGTERMs without landing a kill -- its SIGKILL escalation is gated at
  # half the threshold (2.5%) and RAM bottomed out at 4.74%, while sabnzbd's
  # graceful shutdown took 12 minutes to finish under thrash.
  #
  # systemd-oomd acts on PSI stall time, which does not distinguish waiting on
  # reclaim from waiting on swap I/O, and it SIGKILLs the cgroup outright.
  # Candidates are ranked by reclaim activity, so a service merely holding cold
  # pages in swap (jellyfin sits on ~1.2G of them) is picked last rather than
  # first -- which is what ranking by swap usage would have done.
  #
  # Set here rather than via systemd.oomd.enableSystemSlice, which hardcodes
  # ManagedOOMSwap=kill. oomd.conf defaults apply: act once the slice is fully
  # stalled for 60% of a 10s window, sustained over 30s.
  systemd.slices.system.sliceConfig.ManagedOOMMemoryPressure = "kill";
}

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

  # Userspace last resort. Note this would NOT have caught the 2026-08-07 stall,
  # which was I/O starvation rather than memory exhaustion; it covers the
  # adjacent case where something genuinely runs away with RAM and the kernel
  # OOM killer engages too late to keep the box reachable.
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 5;
  };
}

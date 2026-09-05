{config, ...}: {
  # Mount the Btrfs top level so snapshots are siblings of /persist rather than
  # children of the ephemeral root subvolume.
  fileSystems."/mnt/btrfs" = {
    device = config.fileSystems."/persist".device;
    fsType = "btrfs";
    options = [
      "noatime"
      "subvolid=5"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /mnt/btrfs/.snapshots 0750 root btrbk -"
  ];

  services.btrbk.instances.persist = {
    onCalendar = "hourly";
    snapshotOnly = true;
    settings = {
      timestamp_format = "long";
      snapshot_preserve_min = "24h";
      snapshot_preserve = "7d";
      volume."/mnt/btrfs" = {
        snapshot_dir = ".snapshots";
        subvolume.persist = {};
      };
    };
  };

  systemd.services.btrbk-persist.unitConfig.RequiresMountsFor = ["/mnt/btrfs"];
}

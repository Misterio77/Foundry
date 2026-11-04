{
  # A nested subvolume is excluded from snapshots of its parent.
  systemd.tmpfiles.rules = [
    "v /persist/.snapshots 0750 root btrbk -"
  ];

  services.btrbk.instances.persist = {
    onCalendar = "hourly";
    snapshotOnly = true;
    settings = {
      timestamp_format = "long";
      snapshot_preserve_min = "24h";
      snapshot_preserve = "7d 4w 4m";
      subvolume."/persist" = {
        snapshot_dir = "/persist/.snapshots";
        snapshot_name = "persist";
      };
    };
  };

  systemd.services.btrbk-persist.unitConfig.RequiresMountsFor = ["/persist"];
}

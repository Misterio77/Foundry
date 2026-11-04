{
  config,
  lib,
  ...
}: let
  backup = config.services.postgresqlBackup;
  backupUnits =
    if backup.backupAll
    then ["postgresqlBackup.service"]
    else map (database: "postgresqlBackup-${database}.service") backup.databases;
in {
  services.postgresql.enable = true;
  services.postgresqlBackup = {
    enable = true;
    startAt = "*-*-* 03:45:00";
  };

  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/postgresql";
      user = "postgres";
      group = "postgres";
      mode = "0700";
    }
    {
      directory = backup.location;
      user = "postgres";
      group = "postgres";
      mode = "0700";
    }
  ];

  services.borgbackup.jobs = lib.mkIf (backup.enable && config.networking.hostName == "alcyone") {
    alcyone.paths = [backup.location];
  };

  # Finish dumps before taking the snapshot Borg reads.
  systemd.services.btrbk-persist = lib.mkIf (backup.enable && config.services.btrbk.instances ? persist) {
    requires = backupUnits;
    after = backupUnits;
  };
}

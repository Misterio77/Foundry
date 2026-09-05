{
  services.borgbackup.repos.alcyone = {
    path = "/srv/backups/alcyone";
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHdnvXwdCRqbfVDUL/nil9+OBqK6OjBn1AP75DUvBFpW borg-alcyone@merope"
    ];
  };

  systemd.services.borgbackup-repo-alcyone.unitConfig.RequiresMountsFor = ["/srv/backups"];
}

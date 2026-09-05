{
  config,
  lib,
  pkgs,
  ...
}: let
  snapshotMount = "/run/borgbackup-alcyone-source";
  snapshots = "/mnt/btrfs/.snapshots";
  find = lib.getExe pkgs.findutils;
  mount = lib.getExe' pkgs.util-linux "mount";
  mountpoint = lib.getExe' pkgs.util-linux "mountpoint";
  sort = lib.getExe' pkgs.coreutils "sort";
  tail = lib.getExe' pkgs.coreutils "tail";
  umount = lib.getExe' pkgs.util-linux "umount";
in {
  sops.secrets = {
    borg-passphrase.sopsFile = ../secrets.yaml;
    borg-ssh-key = {
      sopsFile = ../secrets.yaml;
      mode = "0400";
    };
  };

  services.borgbackup.jobs.alcyone = {
    paths = [
      "${snapshotMount}/var/lib/firefly-iii"
      "${snapshotMount}/var/lib/radicale/collections"
      "${snapshotMount}/srv/git"
    ];
    repo = "borg@merope:.";
    doInit = true;
    encryption = {
      mode = "repokey-blake2";
      passCommand = "cat ${config.sops.secrets.borg-passphrase.path}";
    };
    environment.BORG_RSH = "ssh -i ${config.sops.secrets.borg-ssh-key.path} -o IdentitiesOnly=yes";
    compression = "auto,zstd";
    startAt = "*-*-* 04:15:00";
    persistentTimer = true;
    prune.keep = {
      daily = 7;
      weekly = 4;
      monthly = 6;
    };
    preHook = ''
      latest="$(${find} ${snapshots} -mindepth 1 -maxdepth 1 -type d -name 'persist.*' -printf '%f\n' | ${sort} | ${tail} -n 1)"
      if [[ -z "$latest" ]]; then
        echo "No persist snapshot found in ${snapshots}" >&2
        exit 1
      fi

      ${mount} --bind "${snapshots}/$latest" ${snapshotMount}
    '';
    postHook = ''
      if ${mountpoint} --quiet ${snapshotMount}; then
        ${umount} ${snapshotMount}
      fi
    '';
  };

  systemd.services.borgbackup-job-alcyone = {
    wants = ["btrbk-persist.service"];
    after = ["btrbk-persist.service"];
    unitConfig.RequiresMountsFor = ["/mnt/btrfs"];
    serviceConfig = {
      PrivateMounts = true;
      RuntimeDirectory = "borgbackup-alcyone-source";
    };
  };
}

{
  config,
  lib,
  pkgs,
  ...
}: let
  snapshots = "/persist/.snapshots";
  btrfs = lib.getExe' pkgs.btrfs-progs "btrfs";
  find = lib.getExe pkgs.findutils;
  sort = lib.getExe' pkgs.coreutils "sort";
  tail = lib.getExe' pkgs.coreutils "tail";
in {
  options.services.borgbackup.jobs = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
      options.paths = lib.mkOption {
        # Borg runs inside the snapshot; service declarations use live absolute paths.
        apply = paths:
          if name == "alcyone" && paths != null
          then map (lib.removePrefix "/") paths
          else paths;
      };
    }));
  };

  config = {
    sops.secrets = {
      borg-passphrase.sopsFile = ../secrets.yaml;
      borg-ssh-key = {
        sopsFile = ../secrets.yaml;
        mode = "0400";
      };
    };

    services.borgbackup.jobs.alcyone = {
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

        snapshot="${snapshots}/$latest"
        if [[ "$(${btrfs} property get -ts "$snapshot" ro)" != "ro=true" ]]; then
          echo "Refusing to back up a writable snapshot: $snapshot" >&2
          exit 1
        fi

        cd "$snapshot"
      '';
    };

    systemd.services.borgbackup-job-alcyone = {
      requires = ["btrbk-persist.service"];
      after = ["btrbk-persist.service"];
      unitConfig.RequiresMountsFor = ["/persist"];
    };
  };
}

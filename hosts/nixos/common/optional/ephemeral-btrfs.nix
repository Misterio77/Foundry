# This module implements an ephemeral root in btrfs by restoring the 'root' subvolume of ${config.fileSystems."/".device} to 'root-blank' on boot
{
  lib,
  config,
  outputs,
  ...
}: let
  root = config.fileSystems."/";

  wipeScript = ''
    mkdir /tmp -p
    MNTPOINT=$(mktemp -d)
    (
      mount -t btrfs -o subvol=/ ${root.device} "$MNTPOINT"
      trap 'umount "$MNTPOINT"' EXIT

      echo "Creating needed directories"
      mkdir -p "$MNTPOINT"/persist/var/{log,lib/{nixos,systemd}}
      if [ -e "$MNTPOINT/dont-wipe" ]; then
        echo "Skipping wipe"
      else
        echo "Cleaning root subvolume"
        btrfs subvolume delete -R "$MNTPOINT/root"
        echo "Restoring blank subvolume"
        btrfs subvolume snapshot "$MNTPOINT/root-blank" "$MNTPOINT/root"
      fi
    )
  '';

  rootDeviceUnit = outputs.lib.toSystemdDevice root.device;
in {
  boot.initrd = {
    supportedFilesystems = ["btrfs"];
    systemd.services.restore-root = {
      description = "Rollback btrfs rootfs";
      wantedBy = ["initrd.target"];
      requires = [rootDeviceUnit];
      after = [rootDeviceUnit];
      before = ["sysroot.mount"];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = wipeScript;
    };
  };

  fileSystems."/persist".neededForBoot = lib.mkDefault true;
}

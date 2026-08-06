# This file defines the "non-hardware dependent" part of opt-in persistence
# It imports impermanence, defines the basic persisted dirs, and ensures each
# users' home persist dir exists and has the right permissions
#
# It works even if / is tmpfs, btrfs snapshot, or even not ephemeral at all.
{
  lib,
  inputs,
  config,
  ...
}: {
  imports = [inputs.impermanence.nixosModules.impermanence];

  environment.persistence = {
    "/persist" = {
      files = [
        "/etc/machine-id"
      ];
      directories = [
        "/var/lib/fprint"
        "/var/lib/systemd"
        "/var/lib/nixos"
        "/var/log"
        "/srv"
      ];
    };
  };
  # Borrowed snippet from davisschenk/nixos-homelab - thanks!
  #
  # DynamicUser=true services require /var/lib/private to be mode 0700.
  # Impermanence resets it to 0755 on each activation, and systemd-tmpfiles-resetup
  # has RemainAfterExit=true so it won't re-run on subsequent switches to fix it.
  # Fix: force RemainAfterExit=false so tmpfiles re-runs every activation, and
  # also enforce the correct mode on the persist source so impermanence copies 0700.
  # See: https://github.com/nix-community/impermanence/issues/254
  systemd.tmpfiles.rules = [
    "d /persist/var/lib/private 0700 root root -"
    "e /var/lib/private 0700 root root -"
  ];
  systemd.services."systemd-tmpfiles-resetup".serviceConfig.RemainAfterExit = lib.mkForce false; programs.fuse.userAllowOther = true;

  system.activationScripts.persistent-dirs.text = let
    mkHomePersist = user:
      lib.optionalString user.createHome ''
        mkdir -p /persist/${user.home}
        chown ${user.name}:${user.group} /persist/${user.home}
        chmod ${user.homeMode} /persist/${user.home}
      '';
    users = lib.attrValues config.users.users;
  in
    lib.concatLines (map mkHomePersist users);
}

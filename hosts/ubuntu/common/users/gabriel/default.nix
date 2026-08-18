{
  config,
  lib,
  pkgs,
  systemManagerHostName,
  ...
}: let
  inherit (config.users.users.gabriel) home;
in {
  # Ubuntu's logind exec's the per-user `systemd --user` without the nix
  # profiles in XDG_DATA_DIRS. The user-unit search path is fixed when the
  # manager starts, so package-shipped units (home-manager's xdg-desktop-portal
  # services under share/systemd/user) are never found, and environment.d is
  # applied too late to change it. Set XDG_DATA_DIRS on the manager process
  # itself, which also feeds its user D-Bus and services. Missing dirs are
  # ignored; takes effect on the next login.
  environment.etc."systemd/system/user@.service.d/10-nix-xdg-data-dirs.conf".text = ''
    [Service]
    Environment=XDG_DATA_DIRS=${home}/.nix-profile/share:/run/system-manager/sw/share:/usr/local/share:/usr/share
  '';

  users = {
    mutableUsers = true;
    groups.gabriel = {};
    users.gabriel = {
      isNormalUser = true;
      group = "gabriel";
      home = "/home/gabriel";
      createHome = false;
      shell = pkgs.fish;
      ignoreShellProgramCheck = true;
      openssh.authorizedKeys.keys = lib.splitString "\n" (builtins.readFile ../../../../../home/gabriel/ssh.pub);
      extraGroups = [
        "audio"
        "netdev"
        "render"
        "sudo"
        "video"
        "wpa_supplicant"
      ];
    };
  };

  sops.secrets = {
    brave_api_key = {
      sopsFile = ../../../../common/secrets.yaml;
      owner = "gabriel";
    };
    kagi_session_token = {
      sopsFile = ../../../../common/secrets.yaml;
      owner = "gabriel";
    };
  };

  home-manager.users.gabriel = import ../../../../../home/gabriel/${systemManagerHostName}.nix;
}

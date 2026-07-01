{
  pkgs,
  config,
  lib,
  ...
}: let
  ifTheyExist = groups: builtins.filter (group: builtins.hasAttr group config.users.groups) groups;
  lightStartHour = 7;
  darkStartHour = 18;
  homeActivation = config.home-manager.users.gabriel.home.activationPackage;
  activateHomeForTime = pkgs.writeShellScript "activate-home-gabriel-for-time" ''
    set -euo pipefail

    profiles="$HOME/.local/state/nix/profiles"
    base=${homeActivation}

    hour="$(${lib.getExe' pkgs.coreutils "date"} +%H)"
    if [ "$hour" -ge ${toString lightStartHour} ] && [ "$hour" -lt ${toString darkStartHour} ]; then
      specialisation="$base/specialisation/light"
    else
      specialisation="$base/specialisation/dark"
    fi

    eval "$(XDG_RUNTIME_DIR=''${XDG_RUNTIME_DIR:-/run/user/$UID} ${pkgs.systemd}/bin/systemctl --user show-environment 2>/dev/null | ${lib.getExe pkgs.gnused} -En '/^(DBUS_SESSION_BUS_ADDRESS|DISPLAY|WAYLAND_DISPLAY|XAUTHORITY|XDG_RUNTIME_DIR)=/s/^/export /p')"

    # Activate specialisation
    "$specialisation/activate" --driver-version 1
    # Link base config (so that user can switch between them)
    ln -sfT "$base" "$profiles/home-manager-base"
  '';
in {
  users.mutableUsers = false;
  users.users.gabriel = {
    isNormalUser = true;
    shell = pkgs.fish;
    extraGroups = ifTheyExist [
      "audio"
      "deluge"
      "docker"
      "git"
      "i2c"
      "libvirtd"
      "minecraft"
      "mysql"
      "wpa_supplicant"
      "plugdev"
      "podman"
      "tss"
      "video"
      "wheel"
      "wireshark"
    ];

    openssh.authorizedKeys.keys = lib.splitString "\n" (builtins.readFile ../../../../home/gabriel/ssh.pub);
    hashedPasswordFile = config.sops.secrets.gabriel-password.path;
    packages = [pkgs.home-manager];
  };

  sops.secrets = {
    gabriel-password = {
      sopsFile = ../../secrets.yaml;
      neededForUsers = true;
    };
    brave_api_key = {
      sopsFile = ../../secrets.yaml;
      owner = "gabriel";
    };
    kagi_session_token = {
      sopsFile = ../../secrets.yaml;
      owner = "gabriel";
    };
  };

  home-manager.users.gabriel = import ../../../../home/gabriel/${config.networking.hostName}.nix;

  systemd.services.home-manager-gabriel.serviceConfig.ExecStart = lib.mkForce activateHomeForTime;

  security.pam.services = {
    swaylock = {};
    hyprlock = {};
  };
}

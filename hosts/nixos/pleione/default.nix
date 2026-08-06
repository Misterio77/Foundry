{
  inputs,
  config,
  lib,
  ...
}: {
  imports = [
    inputs.hardware.nixosModules.common-gpu-nvidia
    inputs.hardware.nixosModules.common-cpu-intel
    inputs.hardware.nixosModules.common-pc-ssd

    ./hardware-configuration.nix

    ../common/global
    ../common/users/gabriel

    ../common/optional/pipewire.nix
    ../common/optional/quietboot.nix
    ../common/optional/regreet.nix
    ../common/optional/steam-gamescope-session.nix
    ../common/optional/jellyfin-session.nix
    ../common/optional/firefox-session.nix

    ./media-user.nix
  ];

  networking = {
    hostName = "pleione";
    useDHCP = true;
  };

  powerManagement.powertop.enable = true;

  programs.dconf.enable = true;

  services.logind = {
    powerKey = "suspend";
    powerKeyLongPress = "poweroff";
  };

  system.stateVersion = "22.05";
}

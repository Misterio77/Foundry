{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.hardware.nixosModules.common-pc-ssd
    inputs.hardware.nixosModules.framework-13-7040-amd

    ./hardware-configuration.nix

    ../common/global
    ../common/users/gabriel

    ../common/optional/peripherals.nix
    ../common/optional/regreet.nix
    ../common/optional/pipewire.nix
    ../common/optional/quietboot.nix

    ../common/optional/wireless.nix
    ../common/optional/secure-boot.nix
    ../common/optional/cups.nix
  ];

  networking = {
    hostName = "maia";
  };

  boot.kernelPackages = pkgs.linuxKernel.packages.linux_xanmod_latest;

  powerManagement.powertop.enable = true;
  programs.dconf.enable = true;

  system.stateVersion = "22.05";
}

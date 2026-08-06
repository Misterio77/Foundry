{
  imports = [
    ./hardware-configuration.nix
    ./services

    ../common/global
    ../common/users/gabriel
    ../common/optional/docker.nix
  ];

  networking = {
    hostName = "celaeno";
    useDHCP = true;
  };
  system.stateVersion = "22.05";
}

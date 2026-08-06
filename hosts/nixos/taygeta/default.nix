{
  imports = [
    ./hardware-configuration.nix
    ./services

    ../common/global
    ../common/users/gabriel
    ../common/optional/ssh-serve-store.nix
    ../common/optional/nginx.nix
  ];

  networking = {
    hostName = "taygeta";
    useDHCP = true;
  };
  system.stateVersion = "22.11";
}

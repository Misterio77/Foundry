{
  imports = [
    ./hardware-configuration.nix
    ./services

    ../common/global
    ../common/users/gabriel
    ../common/optional/ssh-serve-store.nix
    ../common/optional/nginx.nix
  ];

  nix.settings.max-jobs = 8;

  networking = {
    hostName = "taygeta";
    useDHCP = true;
  };
  system.stateVersion = "22.11";
}

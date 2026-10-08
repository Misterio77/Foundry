{
  imports = [
    ./hardware-configuration.nix
    ./services

    ../common/global
    ../common/users/gabriel
    ../common/optional/ssh-serve-store.nix
    ../common/optional/hydra-builder.nix
    ../common/optional/nginx.nix
  ];

  services.hydra-builder.settings.maxJobs = 8;

  networking = {
    hostName = "taygeta";
    useDHCP = true;
  };
  system.stateVersion = "22.11";
}

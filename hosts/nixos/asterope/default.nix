{
  imports = [
    ./hardware-configuration.nix

    ../common/global
    ../common/users/gabriel
    ../common/optional/fail2ban.nix
  ];

  networking = {
    hostName = "asterope";
    useDHCP = true;
    dhcpcd.IPv6rs = true;
  };

  sops.defaultSopsFile = ./secrets.yaml;
  system.stateVersion = "26.05";
}

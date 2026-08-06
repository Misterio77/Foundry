{
  imports = [
    ./services
    ./hardware-configuration.nix

    ../common/global
    ../common/users/gabriel
    ../common/optional/fail2ban.nix
    ../common/optional/tailscale-exit-node.nix
  ];

  networking = {
    hostName = "alcyone";
    useDHCP = true;
    dhcpcd.IPv6rs = true;
    interfaces.ens3 = {
      useDHCP = true;
      wakeOnLan.enable = true;
      ipv4.addresses = [
        {
          address = "216.238.110.82";
          prefixLength = 23;
        }
      ];
      ipv6.addresses = [
        {
          address = "2001:19f0:b800:1bf8::1";
          prefixLength = 64;
        }
      ];
    };
  };
  system.stateVersion = "22.05";
}

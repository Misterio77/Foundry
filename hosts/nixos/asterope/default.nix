{lib, ...}: {
  imports = [
    ./hardware-configuration.nix
    ./services/stalwart.nix

    ../common/global
    ../common/users/gabriel
    ../common/optional/fail2ban.nix
  ];

  networking = {
    hostName = "asterope";
    useDHCP = true;
    dhcpcd.IPv6rs = true;
    tempAddresses = "disabled";
    interfaces.ens3.ipv6.addresses = [
      {
        address = "2001:19f0:6401:cf2::1";
        prefixLength = 64;
      }
    ];
  };

  services.openssh.settings.PermitRootLogin = lib.mkForce "prohibit-password";
  users.users.root.openssh.authorizedKeys.keyFiles = [../../../home/gabriel/ssh.pub];

  sops.defaultSopsFile = ./secrets.yaml;
  system.stateVersion = "26.05";
}

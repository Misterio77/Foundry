{inputs, ...}: {
  imports = [
    inputs.hardware.nixosModules.raspberry-pi-4

    ./services
    ./hardware-configuration.nix

    ../common/global
    ../common/optional/wireless.nix
    ../common/users/gabriel
  ];

  boot.initrd.systemd.emergencyAccess = true;

  # Static IP address
  networking = {
    hostName = "merope";
    useDHCP = true;
    interfaces = {
      end0 = {
        useDHCP = true;
        wakeOnLan.enable = true;
        ipv4.addresses = [
          {
            address = "192.168.0.11";
            prefixLength = 24;
          }
        ];
        ipv6.addresses = [
          {
            address = "2804:14d:8082:88da::1";
            prefixLength = 64;
          }
        ];
      };
    };
  };

  system.stateVersion = "22.05";
}

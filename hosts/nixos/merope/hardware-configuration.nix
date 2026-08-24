{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ../common/optional/ephemeral-btrfs.nix
    inputs.disko.nixosModules.disko
  ];

  boot = {
    initrd = {
      availableKernelModules = ["xhci_pci"];
    };
    loader.timeout = 5;
  };

  disko.devices.disk = {
    main = {
      device = "/dev/disk/by-id/usb-Argon_Forty_000000000F38-0:0";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          root = {
            size = "100%-512M";
            content = {
              type = "btrfs";
              postCreateHook = ''
                MNTPOINT=$(mktemp -d)
                mount -t btrfs "$device" "$MNTPOINT"
                trap 'umount $MNTPOINT; rm -d $MNTPOINT' EXIT
                btrfs subvolume snapshot -r $MNTPOINT/root $MNTPOINT/root-blank
              '';
              subvolumes = {
                "/root" = {
                  mountOptions = ["compress=zstd"];
                  mountpoint = "/";
                };
                "/nix" = {
                  mountOptions = ["compress=zstd" "noatime"];
                  mountpoint = "/nix";
                };
                "/persist" = {
                  mountOptions = ["compress=zstd"];
                  mountpoint = "/persist";
                };
                "/swap" = {
                  mountOptions = ["compress=zstd" "noatime"];
                  mountpoint = "/swap";
                  swap.swapfile = {
                    size = "8196M";
                    path = "swapfile";
                  };
                };
              };
            };
          };
          boot = {
            size = "512M";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
        };
      };
    };
    sd-card = {
      device = "/dev/disk/by-id/mmc-SS32G_0x95aa1789";
      type = "disk";
      content = {
        type = "gpt";
        partitions.firmware = {
          size = "512M";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/firmware";
          };
        };
      };
    };
    hdd = {
      device = "/dev/disk/by-id/wwn-0x50014ee2c1c1deaa";
      type = "disk";
      content = {
        type = "gpt";
        partitions.media = {
          size = "100%";
          content = {
            type = "btrfs";
            subvolumes = {
              "/media" = {
                mountOptions = ["noatime" "x-systemd.device-bound"];
                mountpoint = "/srv/media";
              };
            };
          };
        };
      };
    };
    hdd2 = {
      device = "/dev/disk/by-id/wwn-0x5000c50090d3963f";
      type = "disk";
      content = {
        type = "gpt";
        partitions.backups = {
          size = "100%";
          content = {
            type = "btrfs";
            subvolumes = {
              "/backups" = {
                mountOptions = ["noatime"];
                mountpoint = "/srv/backups";
              };
            };
          };
        };
      };
    };
  };

  fileSystems."/firmware".neededForBoot = lib.mkDefault true;
  hardware.raspberry-pi = {
    configtxt.settings.all.avoid_warnings = true;
    firmware = {
      enable = true;
      path = "/firmware";
      uboot = {
        enable = true;
        package = pkgs.ubootRaspberryPi4_64bit;
      };
    };
  };

  hardware.raspberry-pi."4" = {
    i2c1.enable = true;
    fkms-3d = {
      enable = true;
      cma = 1024;
    };
  };
  hardware.graphics.enable = true;

  # Avoiding some heavy IO
  nix.settings.auto-optimise-store = false;

  # Enable argonone fan daemon
  services.hardware.argonone.enable = true;

  # Workaround for https://github.com/NixOS/nixpkgs/issues/154163
  nixpkgs.overlays = [
    (_: prev: {makeModulesClosure = x: prev.makeModulesClosure (x // {allowMissing = true;});})
  ];

  nixpkgs.hostPlatform.system = "aarch64-linux";

  # powersave pins all four cores to the 600MHz minimum -- merope never once
  # reached its 1500MHz maximum, including through 4h of sustained 100% load
  # before the 2026-08-07 stall.
  powerManagement.cpuFreqGovernor = "ondemand";
}

{inputs, config, ...}: {
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

  # TODO: migrate to UEFI using (https://github.com/pftf/RPi4), https://wiki.adtya.xyz/nix/nix-on-pi.html
  disko.devices.disk = {
    main = {
      device = "/dev/sdb";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          firmware = {
            size = "30M";
            content = {
              type = "filesystem";
              format = "vfat";
              extraArgs = ["-F" "16"]; # FAT16
              mountpoint = "/firmware";
            };
          };
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
    hdd = {
      device = "/dev/sda";
      type = "disk";
      content = {
        type = "gpt";
        partitions.media = {
          size = "100%";
          content = {
            type = "btrfs";
            subvolumes = {
              "/tv" = {
                mountOptions = ["noatime"];
                mountpoint = "/srv/media/tv";
              };
              "/movies" = {
                mountOptions = ["noatime"];
                mountpoint = "/srv/media/movies";
              };
              "/photos" = {
                mountOptions = ["noatime"];
                mountpoint = "/srv/media/photos";
              };
            };
          };
        };
      };
    };
    hdd2 = {
      device = "/dev/sdc";
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

  powerManagement.cpuFreqGovernor = "powersave";
}

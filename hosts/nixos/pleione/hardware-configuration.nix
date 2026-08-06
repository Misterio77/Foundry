{inputs, lib, ...}: {
  imports = [
    inputs.disko.nixosModules.disko
    ../common/optional/ephemeral-btrfs.nix
    ./remote-control.nix
  ];

  hardware.graphics.enable = true;

  hardware.nvidia = {
    powerManagement = {
      enable = false;
      finegrained = false;
    };
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      nvidiaBusId = "PCI:1@0:0:0";
      intelBusId = "PCI:0@0:2:0";
    };
    # Does not support maxwell gpu
    open = false;
  };

  nixpkgs.hostPlatform.system = "x86_64-linux";
  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "i686-linux"
  ];
  hardware.cpu.amd.updateMicrocode = true;
  powerManagement.cpuFreqGovernor = "ondemand";

  boot = {
    kernelParams = [ "usbcore.autosuspend=-1" ];
    initrd = {
      availableKernelModules = [
        "xhci_pci"
        "ahci"
        "usbhid"
        "usb_storage"
        "sd_mod"
      ];
      kernelModules = ["kvm-intel"];
    };
    loader = {
      systemd-boot = {
        enable = true;
        consoleMode = "max";
      };
      efi.canTouchEfiVariables = true;
    };
  };

  disko.devices.disk.main = {
    device = "/dev/sda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02";
        };
        esp = {
          name = "ESP";
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
        luks = {
          size = "100%";
          content = {
            name = "root";
            type = "luks";
            settings = {
              allowDiscards = true;
              keyFile = "/boot/keyfile";
            };
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
                    size = "16384M";
                    path = "swapfile";
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}

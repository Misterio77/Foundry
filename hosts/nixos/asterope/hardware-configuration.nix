{inputs, ...}: {
  imports = [
    ../common/optional/ephemeral-btrfs.nix
    inputs.disko.nixosModules.disko
  ];

  boot = {
    initrd = {
      availableKernelModules = [
        "ata_piix"
        "sr_mod"
        "uhci_hcd"
        "virtio_blk"
        "virtio_pci"
      ];
    };
  };

  disko.devices.disk.main = {
    device = "/dev/disk/by-path/virtio-pci-0000:00:05.0";
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
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = ["--label" "asterope"];
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
                mountOptions = ["noatime" "compress=zstd"];
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
                  size = "3072M";
                  path = "swapfile";
                };
              };
            };
          };
        };
      };
    };
  };

  hardware.cpu.intel.updateMicrocode = true;

  nixpkgs.hostPlatform = "x86_64-linux";
}

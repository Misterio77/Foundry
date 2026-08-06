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
    loader.grub = {
      enable = true;
      version = 2;
      device = "/dev/vda";
    };
  };

  disko.devices.disk.main = {
    device = "/dev/vda";
    type = "disk";
    # TODO: switch to gpt when reinstalling alcyone, eventually.
    content = {
      type = "table";
      format = "msdos";
      partitions = [{
        content = {
          type = "btrfs";
          postCreateHook = ''
            MNTPOINT=$(mktemp -d)
            mount -t btrfs "$device" "$MNTPOINT"
            trap 'umount $MNTPOINT; rm -d $MNTPOINT' EXIT
            btrfs subvolume snapshot -r $MNTPOINT/root $MNTPOINT/root-blank
          '';
          subvolumes = {
            "/boot" = {
              mountOptions = [];
              mountpoint = "/boot";
            };
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
      }];
    };
  };

  hardware.cpu.intel.updateMicrocode = true;

  virtualisation.hypervGuest.enable = true;
  systemd.services.hv-kvp.unitConfig.ConditionPathExists = ["/dev/vmbus/hv_kvp"];

  nixpkgs.hostPlatform = "x86_64-linux";
}

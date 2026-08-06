{modulesPath, inputs, ...}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    inputs.disko.nixosModules.disko
    ../common/optional/ephemeral-btrfs.nix
  ];

  nixpkgs.hostPlatform.system = "x86_64-linux";
  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "i686-linux"
  ];

  boot = {
    initrd.availableKernelModules = ["ata_piix" "uhci_hcd"];
    kernelModules = ["kvm-intel"];
  };

  disko.devices.disk.main = {
    device = "/dev/vda";
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
      };
    };
  };
}

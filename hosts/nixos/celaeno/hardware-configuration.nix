{inputs, modulesPath, ...}: {
  imports = [
    ../common/optional/ephemeral-btrfs.nix
    (modulesPath + "/profiles/qemu-guest.nix")
    inputs.disko.nixosModules.disko
  ];

  nixpkgs.hostPlatform.system = "aarch64-linux";

  # Slows down write operations considerably
  nix.settings.auto-optimise-store = false;

  boot = {
    initrd = {
      availableKernelModules = [
        "xhci_pci"
        "virtio_pci"
        "usbhid"
      ];
    };
    loader = {
      systemd-boot = {
        enable = true;
        consoleMode = "max";
      };
      efi.canTouchEfiVariables = true;
    };
    # Enable nested virtualization
    extraModprobeConfig = "options kvm nested=1";
  };

  disko.devices.disk.main = {
    device = "/dev/vda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
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

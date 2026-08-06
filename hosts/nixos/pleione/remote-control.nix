{lib, pkgs, ...}: let
  vendor = "1915";
  product = "1025";
in {
  imports = [
    ../common/optional/keyd.nix
  ];

  services.keyd = {
    keyboards = {
      remoteControl = {
        ids = [
          "${vendor}:${product}"
        ];
        settings.main = {
          # Back button
          # Go back (e.g. firefox and steam)
          rightmouse = "mouse1";
          # Mic button
          # Mute sound
          voicecommand = "mute";
        };
      };
    };
  };

  # Avoid suspend wakeup
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", DRIVERS=="usb", ATTRS{idVendor}=="${vendor}", ATTRS{idProduct}=="${product}", ATTR{power/wakeup}="disabled"
  '';
  powerManagement.resumeCommands = ''
    ${pkgs.kmod}/bin/rmmod xhci_pci
    sleep 1
    ${pkgs.kmod}/bin/modprobe xhci_pci
  '';
}

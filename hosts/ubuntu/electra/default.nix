{...}: {
  imports = [
    ../common/global
    ../common/users/gabriel
    ../common/optional/wireless.nix
  ];

  _module.args.systemManagerHostName = "electra";
  nixpkgs.hostPlatform = "x86_64-linux";
  networking.wireless = {
    # system-manager lacks the NixOS D-Bus module that installs its policy.
    dbusControlled = false;
    # empty list requires udev rule for autodetection
    interfaces = ["wlp0s20f3"];
  };
}

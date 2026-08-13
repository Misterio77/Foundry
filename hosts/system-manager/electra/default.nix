{...}: {
  imports = [
    ../common/global
    ../common/users/gabriel
    ../common/optional/wireless.nix
  ];

  _module.args.systemManagerHostName = "electra";
  nixpkgs.hostPlatform = "x86_64-linux";

  # Pinned rather than auto-detected: with an empty list the upstream module
  # installs a udev rule that calls /run/current-system/systemd/bin/systemctl,
  # a path that does not exist outside NixOS.
  networking.wireless.interfaces = ["wlp0s20f3"];
}

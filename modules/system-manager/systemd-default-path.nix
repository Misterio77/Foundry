{
  config,
  lib,
  pkgs,
  ...
}: {
  # Remove once system-manager declares the option required by nixpkgs' systemd library.
  options.systemd.defaultPath = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [];
    description = "Packages appended to the PATH of services using enableDefaultPath.";
  };

  config.systemd.defaultPath = [
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnugrep
    pkgs.gnused
    config.systemd.package
  ];
}

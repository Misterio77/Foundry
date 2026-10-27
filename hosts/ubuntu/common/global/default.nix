{
  inputs,
  outputs,
  pkgs,
  ...
}: let
  dbusSessionConfig = pkgs.runCommandLocal "dbus-session.conf" {} ''
    substitute ${pkgs.dbus}/share/dbus-1/session.conf "$out" \
      --replace-fail \
      '<include ignore_missing="yes">/etc/dbus-1/session.conf</include>' \
      ""
  '';
in {
  imports =
    [
      inputs.home-manager.nixosModules.home-manager
      # Adapt the upstream module's legacy stdenv flags to nixpkgs' platform API.
      ({
        config,
        lib,
        pkgs,
        ...
      }:
        inputs.nix-system-graphics.systemModules.default {
          inherit config lib;
          pkgs =
            pkgs
            // {
              stdenv =
                pkgs.stdenv
                // {
                  inherit (pkgs.stdenv.hostPlatform) isi686 isx86_64;
                };
            };
        })
      ./greetd.nix
      ./network.nix
      ./nix.nix
      ./openssh.nix
      ./pam.nix
      ./sops.nix
    ]
    ++ (builtins.attrValues outputs.systemManagerModules);

  nixpkgs.config.allowUnfree = true;
  system-graphics = {
    enable = true;
    package = pkgs.mesa;
    package32 = pkgs.pkgsi686Linux.mesa;
  };

  # Nix's D-Bus tools use /etc for their primary config, while Ubuntu keeps the
  # defaults in /usr/share and reserves /etc for local includes. Remove the
  # self-include when installing those defaults into /etc.
  environment.etc."dbus-1/session.conf".source = dbusSessionConfig;

  # The management CLI on the system PATH (/run/system-manager/sw/bin), like
  # nixos-rebuild on NixOS, so switching doesn't need `nix run`.
  environment.systemPackages = [
    inputs.system-manager.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  home-manager = {
    useGlobalPkgs = true;
    backupFileExtension = "hm-backup";
    extraSpecialArgs = {
      inherit inputs outputs;
    };
  };
}

{
  inputs,
  outputs,
  pkgs,
  ...
}: let
  dbusSessionConfig =
    builtins.replaceStrings
    ["<include ignore_missing=\"yes\">/etc/dbus-1/session.conf</include>"]
    [""]
    (builtins.readFile "${pkgs.dbus}/share/dbus-1/session.conf");
in {
  imports =
    [
      inputs.home-manager.nixosModules.home-manager
      inputs.nix-system-graphics.systemModules.default
      ./greetd.nix
      ./network.nix
      ./nix.nix
      ./pam.nix
      ./sops.nix
    ]
    ++ (builtins.attrValues outputs.systemManagerModules);

  nixpkgs.config.allowUnfree = true;
  system-graphics.enable = true;

  # Nix's D-Bus tools use /etc for their primary config, while Ubuntu keeps the
  # defaults in /usr/share and reserves /etc for local includes. Remove the
  # self-include when installing those defaults into /etc.
  environment.etc."dbus-1/session.conf".text = dbusSessionConfig;

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

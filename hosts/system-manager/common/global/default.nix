{
  inputs,
  outputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.nix-system-graphics.systemModules.default

    ./greetd.nix
    ./nix.nix
    ./pam.nix
    ./sops.nix
  ];

  nixpkgs.config.allowUnfree = true;
  system-graphics.enable = true;

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

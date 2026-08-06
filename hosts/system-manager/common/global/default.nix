{
  inputs,
  outputs,
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

  home-manager = {
    useGlobalPkgs = true;
    backupFileExtension = "hm-backup";
    extraSpecialArgs = {
      inherit inputs outputs;
    };
  };
}

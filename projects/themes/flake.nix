{
  description = "Personal wallpapers and colorschemes";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default-linux";
  };

  outputs = {
    nixpkgs,
    systems,
    ...
  }: let
    forEachSystem = nixpkgs.lib.genAttrs (import systems);
  in rec {
    packages = forEachSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in rec {
      # My wallpaper collection
      wallpapers = import ./wallpapers {inherit pkgs;};
      allWallpapers = pkgs.linkFarmFromDrvs "wallpapers" (pkgs.lib.attrValues wallpapers);

      # And colorschemes based on it
      generateColorscheme = import ./colorschemes/generator.nix {inherit pkgs;};
      colorschemes = import ./colorschemes {inherit pkgs wallpapers generateColorscheme;};
      allColorschemes = pkgs.linkFarmFromDrvs "colorschemes" (pkgs.lib.attrValues colorschemes);
    });
    hydraJobs = nixpkgs.lib.mapAttrs (_: nixpkgs.lib.filterAttrs (_: nixpkgs.lib.isDerivation)) packages;
  };
}

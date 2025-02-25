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
      allColorschemes = let
        # This is here to help us keep IFD cached (hopefully)
        combined = pkgs.writeText "colorschemes.json" (builtins.toJSON (pkgs.lib.mapAttrs (_: drv: drv.imported) colorschemes));
      in
        pkgs.linkFarmFromDrvs "colorschemes" (pkgs.lib.attrValues colorschemes ++ [combined]);
    });
    hydraJobs = packages;
  };
}

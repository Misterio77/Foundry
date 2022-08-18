{
  description = "My personal website, blog, and digital garden";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.05";
    utils.url = "github:numtide/flake-utils";
    nix-colors.url = "github:misterio77/nix-colors";
  };

  outputs = { self, nixpkgs, utils, nix-colors }: {
    overlays = {
      default = _final: prev: {
        website = rec {
          # Main package, website and capsule fully built into static files
          main = prev.callPackage ./nix/main.nix { inherit css-themes; };

          # CSS themes generated using nix-colors scheme collection
          css-themes = prev.callPackage ./nix/css-themes.nix { inherit nix-colors; };
          # Development shell, puts css-themes in their expected places
          shell = prev.callPackage ./nix/shell.nix { inherit css-themes main; };
          # Quickly serve the website and gemini capsule
          serve = prev.callPackage ./nix/serve.nix { inherit main; };
        };
      };
    };
  } //
  utils.lib.eachDefaultSystem (system:
    let
      mkApp = drv: utils.lib.mkApp { inherit drv; };
      overlays = nixpkgs.lib.attrValues self.overlays;
      pkgs = import nixpkgs { inherit system overlays; };
    in
    {
      packages = rec {
        default = main;
        inherit (pkgs.website) main;
      };
      apps = rec {
        default = serve;
        serve = mkApp pkgs.website.serve;
      };
      devShells = rec {
        default = pkgs.website.shell;
      };
    }
  );
}

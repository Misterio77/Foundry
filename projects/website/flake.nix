{
  description = "My personal website, blog, and digital garden";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
    nix-colors.url = "github:misterio77/nix-colors";
  };

  outputs = { self, nixpkgs, utils, nix-colors }: {
    overlays = {
      default = f: p: {
        misterio-me = rec {
          # Main package, website and capsule fully built into static files
          website = p.callPackage ./nix/website.nix { inherit css-themes; };

          # CSS themes generated using nix-colors scheme collection
          css-themes = p.callPackage ./nix/css-themes.nix { inherit nix-colors; };
          # Development shell, puts css-themes in their expected places
          shell = p.callPackage ./nix/shell.nix { inherit website css-themes; };
          # Quickly serve the website and gemini capsule
          serve = p.callPackage ./nix/serve.nix { inherit website; };
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
        default = website;
        inherit (pkgs.misterio-me) website;
      };
      apps = rec {
        default = serve;
        serve = mkApp pkgs.misterio-me.serve;
        bundle-lock = mkApp pkgs.misterio-me.bundle-lock;
      };
      devShells = rec {
        default = pkgs.misterio-me.shell;
      };
    }
  );
}

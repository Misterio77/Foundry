{
  description = "My personal website, blog, and digital garden";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.05";
    nix-colors.url = "github:misterio77/nix-colors";
  };

  outputs = { self, nixpkgs, nix-colors }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = nixpkgs.legacyPackages;
    in
    rec {
      packages = forAllSystems (system: rec {
        main = pkgsFor.${system}.callPackage ./nix/main.nix { inherit themes; };
        default = main;

        themes = pkgsFor.${system}.callPackage ./nix/themes.nix { inherit nix-colors; };

        serve = pkgsFor.${system}.callPackage ./nix/serve.nix { inherit main; };
        shell = pkgsFor.${system}.callPackage ./nix/shell.nix { inherit themes main; };

      });
      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${packages.${system}.serve}/bin/serve";
        };
      });
      devShells = forAllSystems (system: {
        default = packages.${system}.shell;
      });

      hydraJobs = {
        x86_64-linux.main = packages.x86_64-linux.main;
      };
    };
}

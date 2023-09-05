{
  description = "My personal website and blog";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    systems.url = "github:nix-systems/default-linux";
  };

  outputs = { self, systems, nixpkgs }:
    let
      forAllSystems = f: nixpkgs.lib.genAttrs (import systems) (system: f {
        inherit system;
        pkgs = nixpkgs.legacyPackages.${system};
      });
    in
    rec {
      packages = forAllSystems ({ pkgs, ... }: rec {
        default = pkgs.callPackage ./. { };

        serve = let
          port = 4000;
        in pkgs.writeShellScriptBin "serve-website" ''
          echo "Running in http://localhost:${toString port}"
          ${nixpkgs.lib.getExe pkgs.webfs} -F -p ${toString port} -f index.html -r ${default}/public
        '';
      });

      apps = forAllSystems ({ system, ... }: {
        default = {
          type = "app";
          program = "${packages.${system}.serve}/bin/serve-website";
        };
      });

      hydraJobs = {
        x86_64-linux.main = packages.x86_64-linux.default;
      };
    };
}

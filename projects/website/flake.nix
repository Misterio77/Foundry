{
  description = "My personal website, blog, and digital garden";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let 
        pkgs = import nixpkgs { inherit system; };
        package = "misterio-me";
      in {
        packages.${package} = pkgs.stdenv.mkDerivation {
          pname = package;
          version = "1.0";
          src = ./.;
          buildPhase = ''
            JEKYLL_ENV=production ${pkgs.jekyll}/bin/jekyll build --destination $out
          '';
          installPhase = "true";
        };
        defaultPackage = self.packages.${system}."${package}";

        apps.${package} = let
          serve = pkgs.writeShellScriptBin "serve" ''
            echo "Serving on: http://127.0.0.1:4000"
            ${pkgs.webfs}/bin/webfsd -f index.html -F -p 4000 -r ${self.packages.${system}.${package}}
          '';
        in {
          type = "app";
          program = "${serve}/bin/serve";
        };
        defaultApp = self.apps.${system}.${package};

        devShell =
          pkgs.mkShell { buildInputs = with pkgs; [ jekyll nodePackages.prettier sass scss-lint ]; };
      });
}

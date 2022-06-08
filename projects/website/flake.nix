{
  description = "My personal website, blog, and digital garden";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
    nix-colors.url = "github:misterio77/nix-colors";
  };

  outputs = { self, nixpkgs, utils, nix-colors }: {
    overlays.default = final: prev: {
      misterio-me = final.callPackage ./default.nix { };
      css-themes = final.callPackage ./themes.nix { inherit nix-colors; };
    };
  } //
  utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs { inherit system; overlays = [ self.overlays.default ]; };
      serve = package: pkgs.writeShellScriptBin "serve" ''
        echo "Serving on: http://localhost:8080 and gemini://localhost:1965"
        ${pkgs.webfs}/bin/webfsd -f index.html -F -p 8080 -r ${package}/public & \
        ${pkgs.agate}/bin/agate --content ${package}/public --hostname localhost --certs /tmp/agate-certs & \

        trap 'kill $(jobs -p)' EXIT
        wait
      '';
    in
    rec {
      # Export packages
      packages = rec {
        inherit (pkgs) misterio-me css-themes;
        default = misterio-me;
      };

      # Serve website
      apps = rec {
        misterio-me = {
          type = "app";
          program = "${serve packages.misterio-me}/bin/serve";
        };
        default = misterio-me;
      };

      devShells.default = pkgs.mkShell {
        inputsFrom = [ packages.misterio-me ];
        buildInputs = with pkgs; [ yq openring nodePackages.vscode-langservers-extracted ];
        shellHook = ''
          rm _includes/scheme-datalist.html 2>/dev/null
          rm assets/themes/*.css 2>/dev/null
          mkdir assets/themes -p
          ln -s ${packages.css-themes}/list.html -T $PWD/_includes/scheme-datalist.html
          ln -s ${packages.css-themes}/*.css -t $PWD/assets/themes/
        '';
      };
    }
  );
}

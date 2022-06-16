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
    in
    rec {
      # Export packages
      packages = rec {
        inherit (pkgs) misterio-me css-themes;
        default = misterio-me;
      };

      # Serve website
      apps = rec {
        serve = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "serve" ''
            echo "Serving on: http://localhost:8080 and gemini://localhost:1965"
            ${pkgs.webfs}/bin/webfsd -f index.html -d -F -p 8080 -r ${packages.default}/public & \
            ${pkgs.agate}/bin/agate --content ${packages.default}/public --hostname localhost --certs /tmp/agate-certs & \

            jobs=$(jobs -p)
            trap 'kill $jobs' EXIT
            wait
          ''}/bin/serve";
        };
        default = serve;
      };

      devShells.default = pkgs.mkShell {
        inputsFrom = [ packages.misterio-me ];
        buildInputs = with pkgs; [ yq openring ];
        shellHook = ''
          rm _main/_includes/scheme-datalist.html 2>/dev/null
          rm _main/assets/themes/*.css 2>/dev/null
          mkdir assets/themes -p
          ln -s ${packages.css-themes}/list.html -T $PWD/_main/_includes/scheme-datalist.html
          ln -s ${packages.css-themes}/*.css -t $PWD/_main/assets/themes/
        '';
      };
    }
  );
}

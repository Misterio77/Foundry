{
  description = "My personal website, blog, and digital garden";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
    nix-colors.url = "github:misterio77/nix-colors";
  };

  outputs = { self, nixpkgs, utils, nix-colors }: {
    overlay = final: prev: {
      misterio-me = final.callPackage ./default.nix { };
      css-themes = final.callPackage ./themes.nix { inherit nix-colors; };
    };
  } //
  utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs { inherit system; overlays = [ self.overlay ]; };
      serve = pkgs.writeShellScriptBin "serve" ''
        echo "Serving on: http://localhost:8080 and gemini://localhost:1965"
        ${pkgs.webfs}/bin/webfsd -f index.html -F -p 8080 -r ${self.defaultPackage.${system}}/public & \
        ${pkgs.agate}/bin/agate --content ${self.defaultPackage.${system}}/public --hostname localhost --certs /tmp/agate-certs & \

        trap 'kill $(jobs -p)' EXIT
        wait
      '';
    in
    rec {
      # Export packages
      packages.misterio-me = pkgs.misterio-me;
      packages.css-themes = pkgs.css-themes;
      defaultPackage = packages.misterio-me;

      # Serve website
      apps.misterio-me = {
        type = "app";
        program = "${serve}/bin/serve";
      };
      defaultApp = apps.misterio-me;

      devShell = pkgs.mkShell {
        inputsFrom = [ defaultPackage ];
        buildInputs = with pkgs; [ yq openring nodePackages.vscode-langservers-extracted ];
        shellHook = ''
          rm assets/themes -rf 2> /dev/null
          rm _includes/scheme-datalist.html -f 2> /dev/null
          mkdir assets/themes -p
          cp ${packages.css-themes}/list.html $PWD/_includes/scheme-datalist.html
          cp ${packages.css-themes}/*.css $PWD/assets/themes/
        '';
      };
    }
  );
}

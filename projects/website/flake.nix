{
  description = "My personal website, blog, and digital garden";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }: {
    overlay = final: prev: {
      misterio-me = final.callPackage ./default.nix { };
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
      # Export package
      packages.misterio-me = pkgs.misterio-me;
      defaultPackage = packages.misterio-me;

      # Serve website on devserver
      apps.misterio-me = {
        type = "app";
        program = "${serve}/bin/serve";
      };
      defaultApp = apps.misterio-me;

      devShell = pkgs.mkShell {
        inputsFrom = [ defaultPackage ];
        buildInputs = with pkgs; [ yq openring ];
      };
    }
  );
}

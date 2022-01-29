{
  description = "My personal website, blog, and digital garden";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }: {
    # Exportar como overlay
    overlay = final: prev: {
      misterio-me = final.callPackage ./default.nix { };
    };
  } //
  utils.lib.eachDefaultSystem (system:
    # Importar overlay
    let pkgs = import nixpkgs { inherit system; overlays = [ self.overlay ]; };
    in rec {
      # Exportar como package
      packages.misterio-me = pkgs.misterio-me;
      defaultPackage = packages.misterio-me;

      devShell = pkgs.mkShell {
        inputsFrom = [ defaultPackage ];
      };
    }
  );
}

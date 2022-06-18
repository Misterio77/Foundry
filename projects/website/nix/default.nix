{ self, nixpkgs, utils, nix-colors }: {
  overlays.default = final: _prev:
    import ./packages {
      inherit nix-colors;
      pkgs = final;
    };
} //
utils.lib.eachDefaultSystem (system:
  let
    pkgs = import nixpkgs {
      inherit system;
      overlays = [ self.overlays.default ];
    };
  in
  {
    packages = rec {
      inherit (pkgs) misterio-me;
      default = misterio-me;
    };

    apps = import ./apps { inherit pkgs; };
    devShells = import ./shells { inherit pkgs; };
  })

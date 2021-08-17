{
  description = "My personal website, blog, and digital garden";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.05";

    outputs = { self, nixpkgs, nixpkgs-ruby, flake-utils }:
      flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [ jekyll prettier ];
        };
      });
  };
}

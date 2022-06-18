{ pkgs, nix-colors }: rec {
  default = misterio-me;
  misterio-me = pkgs.callPackage ./misterio-me.nix { };
  css-themes = pkgs.callPackage ./css-themes.nix { inherit nix-colors; };
}

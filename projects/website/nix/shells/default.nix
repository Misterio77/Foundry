{ pkgs }: rec {
  default = development;
  development = pkgs.callPackage ./development.nix { };
}

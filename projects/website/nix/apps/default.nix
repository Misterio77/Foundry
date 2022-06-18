{ pkgs, ... }: let
  serve-drv = pkgs.callPackage ./serve.nix { };
  bundle-lock-drv = pkgs.callPackage ./bundle-lock.nix { };
in rec {
  serve = {
    type = "app";
    program = "${serve-drv}/bin/serve";
  };
  bundle-lock = {
    type = "app";
    program = "${bundle-lock-drv}/bin/bundle-lock";
  };
  default = serve;
}

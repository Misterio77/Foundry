{
  inputs,
  lib,
  pkgs,
  ...
}: let
  # Patch the upstream expression before evaluation; derivation patches run too late.
  upstream = import (builtins.toFile "hytale-flake.nix" (lib.replaceStrings
    ["xorg.libX11" "xorg.libXcursor" "xorg.libXrandr" "xorg.libXi" "xorg.libxcb"]
    ["libx11" "libxcursor" "libxrandr" "libxi" "libxcb"]
    (builtins.readFile "${inputs.hytale}/flake.nix")));
  hytale = upstream.outputs (inputs.hytale.inputs // {self = hytale;});
in {
  home.packages = [hytale.packages.${pkgs.stdenv.hostPlatform.system}.default];
  home.persistence."/persist".directories = [".local/share/Hytale"];
}

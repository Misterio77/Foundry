{
  pkgs,
  lib,
  ...
}: let
  osrsMcp = pkgs.callPackage ./osrs {};
in {
  programs.mcp = {
    enable = true;
    servers.osrs = {
      command = lib.getExe osrsMcp;
      lifecycle = "lazy";
    };
  };
}

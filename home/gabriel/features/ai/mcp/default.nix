{lib, config, ...}: let
  hasPackage = n: lib.any (p: (p.pname or p.name or null) == n) config.home.packages;
in {
  programs.mcp = {
    enable = true;
    servers.osrs = lib.mkIf (hasPackage "runelite") {
      url = "http://127.0.0.1:18471/mcp";
      lifecycle = "lazy";
    };
  };
}

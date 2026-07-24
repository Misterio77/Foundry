{pkgs, ...}: let
  piMcp = pkgs.buildPiPackage {
    pname = "pi-mcp-adapter";
    version = "2.11.0";
    src = pkgs.fetchFromGitHub {
      owner = "nicobailon";
      repo = "pi-mcp-adapter";
      rev = "82724dccc13a49310530898f922bafff12b7f3fe";
      sha256 = "1cwbav9bscdjappi621xwwjc71rmrnj4x1yrdnp5p8fjsgv14di6";
    };
    npmDepsHash = "sha256-LOUtQMmPvYZjvUBV3YEctGAhDV36+YloYS/VaiV0Gc0=";
  };
in {
  programs.pi-coding-agent.settings.packages = [piMcp];
}

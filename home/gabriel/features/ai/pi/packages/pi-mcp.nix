{pkgs, ...}: let
  piMcp = pkgs.buildPiPackage {
    pname = "pi-mcp-adapter";
    version = "2.20.1";
    src = pkgs.fetchFromGitHub {
      owner = "nicobailon";
      repo = "pi-mcp-adapter";
      rev = "1dbdef96f674410ac37067de70f10a3de3d48d98";
      sha256 = "0ql9jwq6xfxrg2mphas9l2ymnzb0d3lgqpb331laqz3arzbpmlcv";
    };
    npmDepsHash = "sha256-5lNYe9Y/LFGBRcLQ2DX3R1S8vbJcA8fmuwl64V9lJfE=";
  };
in {
  programs.pi-coding-agent.settings.packages = [piMcp];
  home.file.".pi/agent/mcp.json".text = builtins.toJSON {
    settings.showStatusIcon = false;
  };
}

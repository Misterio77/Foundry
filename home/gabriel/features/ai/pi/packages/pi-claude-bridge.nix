{
  pkgs,
  lib,
  ...
}: let
  piClaudeBridge = pkgs.buildPiPackage {
    pname = "pi-claude-bridge";
    version = "0.8.0";
    src = pkgs.fetchFromGitHub {
      owner = "elidickinson";
      repo = "pi-claude-bridge";
      rev = "d3cb25e96742c47e77675ba7ff50e181ebb476ef";
      hash = "sha256-/7Ofo9nt74RXaV+01TIzguFxm0FpeNKRXV5Uk67qSGI=";
    };
    npmDepsHash = "sha256-tDUis202Q9TEP1XqBr3p77cLYMKuTvf/ev2bBh26TCI=";
  };
in {
  programs.pi-coding-agent.settings.packages = [piClaudeBridge];
  home.file.".pi/agent/claude-bridge.json".text = builtins.toJSON {
    askClaude.enabled = false;
    provider = {
      plan = "max";
      stripctMcpConfig = true;
      pathToClaudeCodeExecutable = lib.getExe pkgs.claude-code;
    };
  };
}

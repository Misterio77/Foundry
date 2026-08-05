{
  pkgs,
  lib,
  ...
}: let
  piClaudeBridge = pkgs.buildPiPackage {
    pname = "pi-claude-bridge";
    version = "0.6.3";
    src = pkgs.fetchFromGitHub {
      owner = "elidickinson";
      repo = "pi-claude-bridge";
      rev = "066767393a0efe4be09632f63dc046c2190231b7";
      hash = "sha256-vn2geva8IVwR+sloFp+wUt1f16iGVs10vIn2PAtCSWk=";
    };
    npmDepsHash = "sha256-N3HUbMT9YNR3ZTfmRFcLEpWv/0PrcdYr9LDSmAiGZjY=";
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

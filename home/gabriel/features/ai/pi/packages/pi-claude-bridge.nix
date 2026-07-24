{pkgs, lib, ...}: let
  piClaudeBridge = pkgs.buildPiPackage {
    pname = "pi-claude-bridge";
    version = "unstable";
    src = pkgs.fetchFromGitHub {
      owner = "elidickinson";
      repo = "pi-claude-bridge";
      rev = "0c0feef83284b71a7cf2b5779e86ca2e8f75ce4c";
      hash = "sha256-N6hRLcbOlQyQ0coP6YTqn1k5JQlwP/qx/m8tWfySxyI=";
    };
    npmDepsHash = "sha256-cE6NKQZFwZxyr1MjbT8FXlrNyVwMxbN5mHAynmSJEVA=";
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

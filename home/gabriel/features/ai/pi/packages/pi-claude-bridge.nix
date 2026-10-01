{
  pkgs,
  lib,
  ...
}: let
  piClaudeBridge = pkgs.buildPiPackage {
    pname = "pi-claude-bridge";
    version = "0.9.0";
    src = pkgs.fetchFromGitHub {
      owner = "elidickinson";
      repo = "pi-claude-bridge";
      rev = "a78a2a5525e96318f8dba7f9fd32ce2191be0136";
      hash = "sha256-QQSXUo4Z/7oeMmu89D/xPoztKEcKT5V8nDsZwS+xD0M=";
    };
    npmDepsHash = "sha256-/wY2r/wZHnc+7/3VGhjDp+iNujR0IPCZ5m7K+/OnvNU=";
  };
in {
  programs.pi-coding-agent.settings = {
    enabledModels = [
      "claude-bridge/claude-fable-5-1"
      "claude-bridge/claude-opus-5-5"
      "claude-bridge/claude-sonnet-5-5"
    ];
    packages = [piClaudeBridge];
  };
  home.file.".pi/agent/claude-bridge.json".text = builtins.toJSON {
    askClaude.enabled = false;
    provider = {
      plan = "max";
      stripctMcpConfig = true;
      pathToClaudeCodeExecutable = lib.getExe pkgs.claude-code;
    };
  };
}

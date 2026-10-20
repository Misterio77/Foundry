{
  pkgs,
  lib,
  ...
}: let
  piClaudeBridge = pkgs.buildPiPackage {
    pname = "pi-claude-bridge";
    version = "0.9.3";
    src = pkgs.fetchFromGitHub {
      owner = "elidickinson";
      repo = "pi-claude-bridge";
      rev = "874fa7c2678456336f23b64e784e2057e608d83e";
      hash = "sha256-2P81N6xWuvJdB3w7egU8QNguXWkOyyRUDePveXY7p0c=";
    };
    npmDepsHash = "sha256-bVMT1aF7s8tB8DSxSRalN+Bvrh09kuS73oD6dtkzf+g=";
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
      strictMcpConfig = true;
      pathToClaudeCodeExecutable = lib.getExe pkgs.claude-code;
    };
  };
}

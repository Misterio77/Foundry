{
  pkgs,
  lib,
  ...
}: let
  piClaudeBridge = pkgs.buildPiPackage {
    pname = "pi-claude-bridge";
    version = "0.9.1";
    src = pkgs.fetchFromGitHub {
      owner = "elidickinson";
      repo = "pi-claude-bridge";
      rev = "9dafd0301faad79cf6a1974d92af424189476b5d";
      hash = "sha256-Y3uNnHRrcdc3v9PJepG9W+GjBNmq1V9XW08aeV/UM5U=";
    };
    npmDepsHash = "sha256-wwGOr2eWVyQKt6ZQGdzNWj1xYEQYwY0aUaKwObUIxas=";
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

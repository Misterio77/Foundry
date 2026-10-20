{
  lib,
  pkgs,
  ...
}: let
  customExtensions = pkgs.buildPiPackage {
    pname = "extensions";
    version = "unstable";
    src = ./extensions;
    npmDeps = pkgs.importNpmLock {npmRoot = ./extensions;};
    npmConfigHook = pkgs.importNpmLock.npmConfigHook;
  };
in {
  imports = [
    ./theme.nix
    ./packages
  ];

  programs.pi-coding-agent = {
    enable = true;
    context = builtins.readFile ../common/context.md + "\n" + builtins.readFile ./context.md;
    settings = {
      tuiMode = "regular";
      defaultProvider = "openai";
      defaultModel = "gpt-6.1-sol";
      enabledModels = [
        "openai/gpt-6-astra"
        "openai/gpt-6.1-sol"
        "openai/gpt-6-luna"
        "deepseek/flash"
      ];
      skills = [../common/skills];
      prompts = [./prompts];
      extensions = [customExtensions];
      enableInstallTelemetry = false;
    };
    keybindings = {
      "app.editor.external" = ["alt+e"];
    };
  };
  home.sessionVariables = {
    PI_SKIP_VERSION_CHECK = true;
    PI_TELEMETRY = false;
  };
}

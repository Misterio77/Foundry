{
  lib,
  pkgs,
  osConfig,
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
    extraPackages = [
      pkgs.jujutsu # Used by the jj snapshot extension
      pkgs.python3 # Often used
      pkgs.python3Packages.trafilatura # Used by the web-fetch skill
    ];
    context = ./context.md;
    settings = {
      compaction = {
        enabled = true;
        keepRecentTokens = 20000;
        reserveTokens = 16384;
      };
      defaultProvider = "openai-codex";
      defaultModel = "gpt-6-sol";
      enabledModels = [
        "openai-codex/*"
        "deepseek/*"
      ];

      skills = [./skills];
      prompts = [./prompts];
      extensions = [customExtensions];
      enableInstallTelemetry = false;
      webSearch = {
        braveApiKeyFile = osConfig.sops.secrets.brave_api_key.path or null;
        kagiSessionTokenFile = osConfig.sops.secrets.kagi_session_token.path or null;
      };
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

{
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
      defaultModel = "gpt-5.6-sol";
      enabledModels = [
        "openai-codex/gpt-5.6-sol"
        "openai-codex/gpt-5.6-terra"
        "openai-codex/gpt-5.6-luna"
        "claude-bridge/claude-opus-4-8"
        "claude-bridge/claude-sonnet-4-6"
        "claude-bridge/claude-haiku-4-5"
        "llama.cpp/qwen3.6-35b-a3b"
        "llama.cpp/gemma-4-26b-a4b"
      ];

      skills = [./skills];
      prompts = [./prompts];
      extensions = [customExtensions];
      enableInstallTelemetry = false;

      webSearch = {
        braveApiKeyFile = osConfig.sops.secrets.brave_api_key.path;
        kagiSessionTokenFile = osConfig.sops.secrets.kagi_session_token.path;
      };
    };
    keybindings = {
      "app.editor.external" = ["alt+e"];
    };
  };
  home.sessionVariables = {
    LLAMA_BASE_URL = "http://llm.m7.rs";
    PI_SKIP_VERSION_CHECK = true;
    PI_TELEMETRY = false;
  };
}

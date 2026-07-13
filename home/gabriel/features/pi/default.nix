{
  pkgs,
  osConfig,
  lib,
  ...
}: let
  customExtensions = pkgs.buildPiPackage {
    pname = "extensions";
    version = "unstable";
    src = ./extensions;
    npmDeps = pkgs.importNpmLock {npmRoot = ./extensions;};
    npmConfigHook = pkgs.importNpmLock.npmConfigHook;
  };
  piw = pkgs.writeShellApplication {
    name = "piw";
    runtimeInputs = [
      pkgs.jujutsu
      pkgs.pi-coding-agent
    ];
    text = builtins.readFile ./piw.sh;
  };
in {
  imports = [
    ./theme.nix
    ./packages
  ];

  programs.pi-coding-agent = {
    enable = true;
    extraPackages = [pkgs.python3Packages.trafilatura]; # Used by the web-fetch skill
    context = ./context.md;
    settings = {
      compaction = {
        enabled = true;
        keepRecentTokens = 20000;
        reserveTokens = 16384;
      };
      defaultModel = "gpt-5.6-sol";
      enabledModels = [
        "openai-codex/gpt-5.6-sol"
        "openai-codex/gpt-5.6-terra"
        "openai-codex/gpt-5.6-luna"
        "claude-bridge/claude-opus-4-8"
        "claude-bridge/claude-sonnet-4-6"
        "claude-bridge/claude-haiku-4-5"
        "qwen3.6"
        "gemma-4"
      ];

      skills = [./skills];
      prompts = [./prompts];
      extensions = [customExtensions];

      webSearch = {
        braveApiKeyFile = osConfig.sops.secrets.brave_api_key.path;
        kagiSessionTokenFile = osConfig.sops.secrets.kagi_session_token.path;
      };

      gondolin = {
        qemuPath = lib.getExe pkgs.qemu;
        httpProxy = {
          allowedHosts = ["api.github.com" "firefly.m7.rs"];
          secrets = {
            GITHUB_TOKEN = {
              hosts = ["api.github.com"];
              cmd = "gh auth token";
            };
            FIREFLY_TOKEN = {
              hosts = ["firefly.m7.rs"];
              cmd = "pass firefly.m7.rs/pi-pat";
            };
          };
        };
      };
    };
    keybindings = {
      "app.editor.external" = ["alt+e"];
    };
  };
  home.packages = [piw];
  home.sessionVariables.PI_OFFLINE = true;
}

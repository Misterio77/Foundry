{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: {
  imports = [inputs.paseo.nixosModules.default];

  services.paseo = {
    enable = true;
    package = inputs.paseo.packages.${pkgs.system}.default.overrideAttrs (old: {
      # Upstream's daemon-only source filter excludes the web app sources.
      src = inputs.paseo;
      postBuild =
        (old.postBuild or "")
        + ''
          npm run build:daemon-web-ui
        '';
      postInstall =
        (old.postInstall or "")
        + ''
          cp -a packages/server/dist/server/web-ui \
            $out/lib/paseo/packages/server/dist/server/
        '';
    });
    user = "gabriel";
    group = "users";
    listenAddress = "0.0.0.0";
    relay.enable = false;
    settings = {
      daemon = {
        mcp = {
          enabled = true;
          injectIntoAgents = true;
        };
        browserTools.enabled = false;
        autoArchiveAfterMerge = false;
        enableTerminalAgentHooks = false;
        hostnames = [config.networking.hostName];
      };
      agents = {
        providers = {
          claude.enabled = false;
          codex.enabled = false;
          copilot.enabled = false;
          opencode.enabled = false;
          omp.enabled = false;
          pi.enabled = true;
        };
        metadataGeneration.providers = [];
      };
      features = {
        dictation.enabled = true;
        voiceMode = {
          enabled = true;
          llm.provider = "pi";
          stt = {
            provider = "local";
            model = "parakeet-tdt-0.6b-v3-int8";
          };
          tts = {
            provider = "local";
            model = "kokoro-en-v0_19";
            speakerId = 0;
          };
        };
        webUi.enabled = true;
      };
    };
  };

  sops.secrets.paseo-password.sopsFile = ../secrets.yaml;
  systemd.services.paseo.serviceConfig = {
    ExecStart = lib.mkForce (pkgs.writeShellScript "paseo-server" ''
      export PASEO_PASSWORD="$(<"$CREDENTIALS_DIRECTORY/paseo-password")"
      exec ${config.services.paseo.package}/bin/paseo-server
    '');
    LoadCredential = "paseo-password:${config.sops.secrets.paseo-password.path}";
  };

  # Reachable directly over the tailnet, but not from LAN/public interfaces.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [6767];
}

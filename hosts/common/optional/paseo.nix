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
    user = "gabriel";
    group = "users";
    listenAddress = "0.0.0.0";
    relay.enable = false;
    settings = {
      daemon = {
        mcp.enabled = false;
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
        };
        metadataGeneration.providers = [];
      };
      features = {
        dictation.enabled = true;
        voiceMode.enabled = true;
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

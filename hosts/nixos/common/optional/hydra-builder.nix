{
  config,
  pkgs,
  outputs,
  ...
}: let
  coordinator = outputs.nixosConfigurations.celaeno.config;
in {
  services.hydra-builder = {
    enable = true;
    queueRunnerAddr = "http://${coordinator.networking.hostName}:${toString coordinator.services.hydra.queueRunner.grpc.port}";
    authorizationFile = config.sops.secrets.hydra-builder-token.path;
    settings = {
      systems = [pkgs.stdenv.hostPlatform.system];
      supportedFeatures = ["kvm" "big-parallel" "nixos-test"];
    };
  };

  systemd.services.hydra-builder = {
    wants = ["tailscale-online.target"];
    after = ["tailscale-online.target"];
  };

  sops.secrets.hydra-builder-token = {
    sopsFile = ../secrets.yaml;
    owner = "hydra-builder";
    mode = "0400";
    restartUnits = ["hydra-builder.service"];
  };
}

{config, ...}: {
  services.prometheus.exporters = {
    node = {
      enable = true;
      enabledCollectors = ["systemd"];
      extraFlags = [
        "--collector.diskstats.device-exclude=^(z?ram|loop|fd)[0-9]+$"
      ];
    };
    nix-registry.enable = true;
  };

  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPorts = [
      config.services.prometheus.exporters.node.port
      config.services.prometheus.exporters.nix-registry.port
    ];
  };
}

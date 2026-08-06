{config, ...}: {
  services.prometheus.exporters = {
    node = {
      enable = true;
      enabledCollectors = ["systemd"];
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

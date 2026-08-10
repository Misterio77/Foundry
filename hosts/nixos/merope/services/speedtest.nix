{config, ...}: {
  services.prometheus.exporters.speedtest.enable = true;

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    config.services.prometheus.exporters.speedtest.port
  ];
}

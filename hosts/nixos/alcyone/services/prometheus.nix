{
  config,
  outputs,
  lib,
  ...
}: let
  hosts = lib.attrNames outputs.nixosConfigurations;
in {
  services = {
    prometheus = {
      enable = true;
      globalConfig = {
        # Scrape a bit more frequently
        scrape_interval = "30s";
      };
      scrapeConfigs = [
        {
          job_name = "hydra";
          scheme = "https";
          static_configs = [{targets = ["hydra.m7.rs"];}];
        }
        {
          job_name = "headscale";
          scheme = "https";
          static_configs = [{targets = ["tailscale.m7.rs"];}];
        }
        {
          job_name = "grafana";
          scheme = "https";
          static_configs = [{targets = ["dash.m7.rs"];}];
        }
        {
          job_name = "prometheus";
          scheme = "https";
          static_configs = [{targets = ["metrics.m7.rs"];}];
        }
        {
          job_name = "jellyfin";
          scheme = "https";
          static_configs = [{targets = ["media.m7.rs"];}];
        }
        {
          job_name = "nginx";
          scheme = "https";
          static_configs = [
            {
              targets = [
                "alcyone.m7.rs"
                "celaeno.m7.rs"
                "merope.m7.rs"
              ];
            }
          ];
        }
        {
          job_name = "hosts";
          scheme = "http";
          static_configs =
            map (hostname: {
              targets = [
                "${hostname}:${toString config.services.prometheus.exporters.node.port}"
                "${hostname}:${toString config.services.prometheus.exporters.nix-registry.port}"
              ];
              labels.instance = hostname;
            })
            hosts;
        }
      ];
      extraFlags = let
        prometheus = config.services.prometheus.package;
      in [
        # Custom consoles
        "--web.console.templates=${prometheus}/etc/prometheus/consoles"
        "--web.console.libraries=${prometheus}/etc/prometheus/console_libraries"
      ];
    };
    nginx.virtualHosts = {
      "metrics.m7.rs" = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://localhost:${toString config.services.prometheus.port}";
          extraConfig = ''
            allow 127.0.0.1;
            allow ::1;
            allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v4};
            allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v6};
            deny all;
          '';
        };
      };
    };
  };

  environment.persistence = {
    "/persist".directories = [{
      directory = "/var/lib/prometheus2";
      user = "prometheus";
      group = "prometheus";
      mode = "0700";
    }];
  };
}

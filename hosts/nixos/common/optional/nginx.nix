{
  lib,
  config,
  outputs,
  ...
}: let
  inherit (config.networking) hostName;
in {
  imports = [./nginx-unavailable.nix];

  sops.secrets.metrics-client-ca = {
    sopsFile = ../secrets.yaml;
    owner = config.services.nginx.user;
    mode = "0400";
    restartUnits = ["nginx.service"];
  };

  services = {
    nginx = {
      enable = true;
      recommendedTlsSettings = true;
      recommendedProxySettings = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      clientMaxBodySize = "300m";

      appendHttpConfig = ''
        ssl_client_certificate ${config.sops.secrets.metrics-client-ca.path};
        ssl_verify_client optional;
      '';
      virtualHosts."${hostName}.m7.rs" = {
        default = true;
        forceSSL = true;
        enableACME = true;
        locations."/metrics" = {
          proxyPass = "http://localhost:${toString config.services.prometheus.exporters.nginxlog.port}";
          extraConfig =
            if config.services.nginx.virtualHosts."${hostName}.m7.rs".forceSSL
            then ''
              if ($ssl_client_verify != SUCCESS) {
                return 403;
              }
            ''
            else ''
              allow 127.0.0.1;
              allow ::1;
              allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v4};
              allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v6};
              deny all;
            '';
        };
      };
    };

    prometheus.exporters.nginxlog = {
      enable = true;
      group = "nginx";
      settings.namespaces = [
        {
          name = "filelogger";
          source.files = ["/var/log/nginx/access.log"];
          format = "$remote_addr - $remote_user [$time_local] \"$request\" $status $body_bytes_sent \"$http_referer\" \"$http_user_agent\"";
        }
      ];
    };

    uwsgi = {
      enable = true;
      user = "nginx";
      group = "nginx";
      plugins = ["cgi"];
      instance = {
        type = "emperor";
        vassals = lib.mkBefore {};
      };
    };
  };
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  # Enable acme for usage with nginx vhosts
  security.acme = {
    defaults.email = "eu@misterio.me";
    acceptTerms = true;
  };

  environment.persistence = {
    "/persist".directories = [
      {
        directory = "/var/lib/acme";
        user = "acme";
        group = "acme";
        mode = "0700";
      }
    ];
  };
}

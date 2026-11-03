{
  config,
  inputs,
  pkgs,
  ...
}: let
  components = config.services.authentik.authentikComponents;
  # Blueprint retrieval rejects symlinks resolving outside blueprints_dir.
  blueprints = pkgs.runCommand "authentik-blueprints" {} ''
    cp -rL ${components.staticWorkdirDeps}/blueprints "$out"
    chmod u+w "$out"
    cp ${./authentik/foundry.yaml} "$out/foundry.yaml"
  '';
in {
  imports = [inputs.authentik-nix.nixosModules.default];

  sops.secrets = {
    authentik-key.sopsFile = ../secrets.yaml;
    authentik-grafana-client-secret = {
      sopsFile = ../secrets.yaml;
      owner = "grafana";
      restartUnits = ["grafana.service"];
    };
  };
  sops.templates.authentik-env = {
    content = ''
      AUTHENTIK_SECRET_KEY=${config.sops.placeholder.authentik-key}
      AUTHENTIK_GRAFANA_CLIENT_SECRET=${config.sops.placeholder.authentik-grafana-client-secret}
    '';
    restartUnits = ["authentik-migrate.service" "authentik-worker.service" "authentik.service"];
  };

  services.authentik = {
    enable = true;
    environmentFile = config.sops.templates.authentik-env.path;
    settings = {
      blueprints_dir = blueprints;
      cert_discovery_dir = "${pkgs.emptyDirectory}";
      disable_startup_analytics = true;
      avatars = "initials";
      storage.file.path = "/var/lib/authentik/data";
      listen = {
        http = ["127.0.0.1:9000"];
        https = ["127.0.0.1:9443"];
        metrics = ["127.0.0.1:9300"];
        trusted_proxy_cidrs = ["127.0.0.1/32" "::1/128"];
      };
      outposts.disable_embedded_outpost = true;
    };
    worker = {
      listenHTTP = "127.0.0.1:9001";
      listenMetrics = "127.0.0.1:9301";
    };
  };

  # Importing the community module must not upgrade the shared database cluster.
  services.postgresql.package = pkgs.postgresql_14;
  services.postgresqlBackup = {
    enable = true;
    databases = ["authentik"];
    startAt = "*-*-* 03:45:00";
  };

  services.nginx.virtualHosts."auth.m7.rs" = {
    forceSSL = true;
    enableACME = true;
    extraConfig = ''
      allow 127.0.0.1;
      allow ::1;
      allow ${config.services.headscale.settings.prefixes.v4};
      allow ${config.services.headscale.settings.prefixes.v6};
      deny all;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:9000";
      proxyWebsockets = true;
      recommendedProxySettings = false;
      # Discard client-supplied forwarding chains at the only trusted proxy.
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
      '';
    };
  };

  environment.persistence."/persist".directories = [
    # DynamicUser's StateDirectory lives here, not at its public symlink.
    {
      directory = "/var/lib/private/authentik";
      mode = "0700";
    }
    {
      directory = config.services.postgresqlBackup.location;
      user = "postgres";
      group = "postgres";
      mode = "0700";
    }
  ];

  services.prometheus.scrapeConfigs = [
    {
      job_name = "authentik";
      static_configs = [{targets = ["127.0.0.1:9300" "127.0.0.1:9301"];}];
    }
  ];

  # Finish the dump before taking the snapshot Borg reads.
  systemd.services.btrbk-persist = {
    requires = ["postgresqlBackup-authentik.service"];
    after = ["postgresqlBackup-authentik.service"];
  };
}

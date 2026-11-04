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
    cp ${./authentik/calibre-web.yaml} "$out/calibre-web.yaml"
    cp ${./authentik/recovery.yaml} "$out/recovery.yaml"
  '';
in {
  imports = [inputs.authentik-nix.nixosModules.default];

  sops.secrets = {
    authentik-key.sopsFile = ../secrets.yaml;
    authentik-immich-client-secret.sopsFile = ../secrets.yaml;
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
      AUTHENTIK_IMMICH_CLIENT_SECRET=${config.sops.placeholder.authentik-immich-client-secret}
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
      email = {
        host = "127.0.0.1";
        port = 25;
        username = "";
        password = "";
        use_tls = false;
        use_ssl = false;
        from = "Foundry accounts <authentik@m7.rs>";
      };
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
  services.postgresqlBackup.databases = ["authentik"];

  services.nginx.virtualHosts."auth.m7.rs" = {
    forceSSL = true;
    enableACME = true;
    locations."= /metrics".proxyPass = "http://127.0.0.1:9300/metrics";
    locations."= /metrics/worker".proxyPass = "http://127.0.0.1:9301/metrics";
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

  services.borgbackup.jobs.alcyone.paths = ["/var/lib/private/authentik"];

  environment.persistence."/persist".directories = [
    # DynamicUser's StateDirectory lives here, not at its public symlink.
    {
      directory = "/var/lib/private/authentik";
      mode = "0700";
    }
  ];
}

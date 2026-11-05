{
  config,
  inputs,
  pkgs,
  ...
}: let
  components = config.services.authentik.authentikComponents;
  metricsAccess = ''
    allow 127.0.0.1;
    allow ::1;
    allow ${config.services.headscale.settings.prefixes.v4};
    allow ${config.services.headscale.settings.prefixes.v6};
    deny all;
  '';
  # Blueprint retrieval rejects symlinks resolving outside blueprints_dir.
  blueprints = pkgs.runCommand "authentik-blueprints" {} ''
    cp -rL ${components.staticWorkdirDeps}/blueprints "$out"
    chmod -R u+w "$out"
    # These strings are stored verbatim, not translated by the UI locale.
    substituteInPlace "$out/default/flow-password-change.yaml" \
      --replace-fail 'label: Password (repeat)' 'label: Confirmar senha' \
      --replace-fail 'placeholder: Password (repeat)' 'placeholder: Confirmar senha' \
      --replace-fail 'label: Password' 'label: Senha' \
      --replace-fail 'placeholder: Password' 'placeholder: Senha' \
      --replace-fail 'Password needs to be 8 characters or longer.' 'Use uma senha forte com pelo menos 8 caracteres.' \
      --replace-fail 'name: Change Password' 'name: Alterar senha' \
      --replace-fail 'title: Change password' 'title: Alterar sua senha'
    substituteInPlace "$out/default/flow-default-user-settings-flow.yaml" \
      --replace-fail 'label: Username' 'label: Nome de usuário' \
      --replace-fail 'placeholder: Username' 'placeholder: Nome de usuário' \
      --replace-fail 'label: Name' 'label: Nome' \
      --replace-fail 'placeholder: Name' 'placeholder: Nome' \
      --replace-fail 'label: Email' 'label: E-mail' \
      --replace-fail 'placeholder: Email' 'placeholder: E-mail' \
      --replace-fail 'label: Locale' 'label: Idioma' \
      --replace-fail 'placeholder: Locale' 'placeholder: Idioma' \
      --replace-fail 'Not allowed to change email address.' 'Você não pode alterar seu endereço de e-mail.' \
      --replace-fail 'Not allowed to change name.' 'Você não pode alterar seu nome.' \
      --replace-fail 'Not allowed to change username.' 'Você não pode alterar seu nome de usuário.' \
      --replace-fail 'name: User settings' 'name: Minha conta' \
      --replace-fail 'title: Update your info' 'title: Atualizar seus dados'
    substituteInPlace "$out/default/flow-default-authenticator-totp-setup.yaml" \
      --replace-fail 'friendly_name: TOTP Device' 'friendly_name: Aplicativo autenticador' \
      --replace-fail 'title: Set up Two-Factor authentication' 'title: Configurar aplicativo autenticador'
    substituteInPlace "$out/default/flow-default-authenticator-webauthn-setup.yaml" \
      --replace-fail 'friendly_name: WebAuthn device' 'friendly_name: Chave de acesso' \
      --replace-fail 'title: Setup WebAuthn' 'title: Configurar chave de acesso'
    cp ${./authentik/foundry.yaml} "$out/foundry.yaml"
    cp ${./authentik/grafana.yaml} "$out/grafana.yaml"
    cp ${./authentik/immich.yaml} "$out/immich.yaml"
    cp ${./authentik/recovery.yaml} "$out/recovery.yaml"
    cp ${./authentik/jellyfin.yaml} "$out/jellyfin.yaml"
    cp ${./authentik/seerr.yaml} "$out/seerr.yaml"
  '';
in {
  imports = [inputs.authentik-nix.nixosModules.default];

  sops.secrets = {
    authentik-jellyfin-client-secret.sopsFile = ../secrets.yaml;
    authentik-seerr-client-secret.sopsFile = ../secrets.yaml;
    authentik-key.sopsFile = ../secrets.yaml;
    authentik-immich-client-secret.sopsFile = ../secrets.yaml;
    authentik-mail-password.sopsFile = ../secrets.yaml;
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
      AUTHENTIK_EMAIL__PASSWORD=${config.sops.placeholder.authentik-mail-password}
      AUTHENTIK_JELLYFIN_CLIENT_SECRET=${config.sops.placeholder.authentik-jellyfin-client-secret}
      AUTHENTIK_SEERR_CLIENT_SECRET=${config.sops.placeholder.authentik-seerr-client-secret}
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
        host = "mail.m7.rs";
        port = 465;
        username = "auth@m7.rs";
        use_tls = false;
        use_ssl = true;
        from = "Gablogin <auth@m7.rs>";
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

  # Tenant footer settings aren't exposed by the Blueprint serializer.
  systemd.services.authentik-migrate.postStart = ''
    ${components.manage}/bin/manage.py shell <<'PY'
    from authentik.tenants.utils import get_current_tenant

    tenant = get_current_tenant()
    home = {"name": "Voltar ao início", "href": "https://auth.m7.rs/"}
    links = [home] + [link for link in tenant.footer_links if link.get("href") != home["href"]]
    if tenant.footer_links != links:
        tenant.footer_links = links
        tenant.save(update_fields=["footer_links"])
    PY
  '';

  # Importing the community module must not upgrade the shared database cluster.
  services.postgresql.package = pkgs.postgresql_14;
  services.postgresqlBackup.databases = ["authentik"];

  services.nginx.virtualHosts."auth.m7.rs" = {
    forceSSL = true;
    enableACME = true;
    locations."/branding/".alias = "${./authentik/branding}/";
    locations."= /metrics" = {
      proxyPass = "http://127.0.0.1:9300/metrics";
      extraConfig = metricsAccess;
    };
    locations."= /metrics/worker" = {
      proxyPass = "http://127.0.0.1:9301/metrics";
      extraConfig = metricsAccess;
    };
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

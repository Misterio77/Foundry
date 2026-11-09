{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  components = config.services.authentik.authentikComponents;
  homarrIcons = lib.mapAttrs (name: hash:
    pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/homarr-labs/dashboard-icons/59f1e9a4108f4f510f41e9588f078631de1e1405/svg/${name}.svg";
      inherit hash;
    }) {
    grafana = "sha256-jzKJcHPuk1lKsjOUgu8hyjdnBEBV2oniuvkGbSVZLfc=";
    immich = "sha256-pdSkOJnmP/x+lyRgNPf2PN/cQQqoA8VxPVRSkGAcTYk=";
    jellyfin = "sha256-f1PPCD27MRnsjFrL2AScUDMidhfkYVQPcFkawQkSQwY=";
    radicale = "sha256-gFC+Re6xo/zoCV2Ax0DWBVwm48tZ0QWIum/TOSz41Nc=";
    seerr = "sha256-sS5d/WQdlhz7aDYNoz/iiHO5Xqm2TCMjPVuHo3y/pMQ=";
  };
  icons =
    homarrIcons
    // {
      sogo = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/Alinto/sogo/ff2819278518d09fe3e3a8eed013fa0ddd3a022c/UI/WebServerResources/img/sogo-compact.svg";
        hash = "sha256-l9dzTMqv6TrE89YVTTf5C2BWadvRKUcdhAcpOgWDDqg=";
      };
    };
  branding = pkgs.linkFarm "authentik-branding" (
    map (name: {
      inherit name;
      path = ./branding + "/${name}";
    }) (builtins.attrNames (builtins.readDir ./branding))
    ++ lib.mapAttrsToList (name: path: {
      name = "${name}.svg";
      inherit path;
    })
    icons
  );
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
    cp ${./identity.yaml} "$out/identity.yaml"
    cp ${./branding.yaml} "$out/branding.yaml"
    cp ${./authorization.yaml} "$out/authorization.yaml"
    cp ${./grafana.yaml} "$out/grafana.yaml"
    cp ${./immich.yaml} "$out/immich.yaml"
    cp ${./recovery.yaml} "$out/recovery.yaml"
    cp ${./sensitive-changes.yaml} "$out/sensitive-changes.yaml"
    cp ${./password-guessing.yaml} "$out/password-guessing.yaml"
    cp ${./jellyfin.yaml} "$out/jellyfin.yaml"
    cp ${./seerr.yaml} "$out/seerr.yaml"
    cp ${./mail.yaml} "$out/mail.yaml"
    cp ${./calibre-web.yaml} "$out/calibre-web.yaml"
    cp ${./dav.yaml} "$out/dav.yaml"
    cp ${./firefly.yaml} "$out/firefly.yaml"
    cp ${./outposts.yaml} "$out/outposts.yaml"
    cp ${./dav-directory.yaml} "$out/dav-directory.yaml"
    cp ${./mail-and-dav.yaml} "$out/mail-and-dav.yaml"
    cp ${./sogo.yaml} "$out/sogo.yaml"
  '';
in {
  imports = [inputs.authentik-nix.nixosModules.default];

  sops.secrets = {
    authentik-jellyfin-client-secret.sopsFile = ../../secrets.yaml;
    authentik-seerr-client-secret.sopsFile = ../../secrets.yaml;
    authentik-sogo-client-secret.sopsFile = ../../secrets.yaml;
    authentik-key.sopsFile = ../../secrets.yaml;
    authentik-immich-client-secret.sopsFile = ../../secrets.yaml;
    authentik-mail-password.sopsFile = ../../secrets.yaml;
    authentik-grafana-client-secret = {
      sopsFile = ../../secrets.yaml;
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
      AUTHENTIK_SOGO_CLIENT_SECRET=${config.sops.placeholder.authentik-sogo-client-secret}
      AUTHENTIK_RADICALE_DIRECTORY_TOKEN=${config.sops.placeholder.authentik-radicale-directory-token}
    '';
    restartUnits = ["authentik-migrate.service" "authentik-worker.service" "authentik.service"];
  };

  # MFA deletion still bypasses fresh authentication; tracked upstream:
  # https://github.com/goauthentik/authentik/issues/6798
  services.authentik = {
    enable = true;
    authentikComponents = pkgs.authentikComponents;
    environmentFile = config.sops.templates.authentik-env.path;
    settings = {
      blueprints_dir = blueprints;
      cert_discovery_dir = "${pkgs.emptyDirectory}";
      disable_startup_analytics = true;
      default_user_change_username = true;
      default_user_change_email = true;
      reputation.expiry = 900;
      email = {
        host = "mail.m7.rs";
        port = 465;
        username = "auth@m7.rs";
        use_tls = false;
        use_ssl = true;
        from = "Gablogin <auth@m7.rs>";
      };
      avatars = "https://avatars.m7.rs/%(username)s.png,initials";
      storage.file.path = "/var/lib/authentik/data";
      listen = {
        http = ["127.0.0.1:9000"];
        https = ["127.0.0.1:9443"];
        metrics = ["127.0.0.1:9300"];
        trusted_proxy_cidrs = ["127.0.0.1/32" "::1/128"];
      };
      outposts.disable_embedded_outpost = false;
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
    locations."/branding/".alias = "${branding}/";
    # Merope reaches the embedded outpost over verified HTTPS, not an exposed port.
    locations."^~ /books-outpost/" = {
      proxyPass = "http://127.0.0.1:9000/outpost.goauthentik.io/";
      recommendedProxySettings = false;
      extraConfig = ''
        proxy_set_header Host books.m7.rs;
        proxy_set_header X-Original-URL https://books.m7.rs/;
        proxy_set_header X-Forwarded-Host books.m7.rs;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header Authorization "";
      '';
    };
    locations."= /metrics" = {
      proxyPass = "http://127.0.0.1:9300/metrics";
      extraConfig = ''
        if ($ssl_client_verify != SUCCESS) {
          return 403;
        }
      '';
    };
    locations."= /metrics/worker" = {
      proxyPass = "http://127.0.0.1:9301/metrics";
      extraConfig = ''
        if ($ssl_client_verify != SUCCESS) {
          return 403;
        }
      '';
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

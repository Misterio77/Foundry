{
  config,
  lib,
  pkgs,
  ...
}: let
  hostname = "mail.lumis.cards";
  introspection = pkgs.runCommand "stalwart-introspection.py" {nativeBuildInputs = [pkgs.python3];} ''
    cp ${./introspection.py} introspection.py
    cp ${./test_introspection.py} test_introspection.py
    python3 -B test_introspection.py
    cp introspection.py "$out"
  '';
  isFileReference = value:
    lib.isAttrs value
    && builtins.attrNames value == ["file"]
    && (lib.isString value.file || lib.isPath value.file);
  credentialName = file: "secret-${builtins.hashString "sha256" (toString file)}";
  collectFiles = value:
    if isFileReference value
    then [(toString value.file)]
    else if lib.isList value
    then lib.concatMap collectFiles value
    else if lib.isAttrs value
    then lib.concatMap collectFiles (builtins.attrValues value)
    else [];
  rewriteFiles = value:
    if isFileReference value
    then "%{file:/run/credentials/stalwart.service/${credentialName value.file}}%"
    else if lib.isList value
    then map rewriteFiles value
    else if lib.isAttrs value
    then lib.mapAttrs (_: rewriteFiles) value
    else value;
  files = lib.unique (collectFiles settings);
  privateAccess = ''
    allow 127.0.0.1;
    allow ::1;
    allow 100.77.0.0/24;
    allow fd7a:115c:a1e0:77::/64;
    deny all;
  '';
  settings = {
    # Keep Nix settings local without hiding database defaults and signing keys.
    config.local-keys = [
      "store.*"
      "directory.*"
      "tracer.*"
      "!server.blocked-ip.*"
      "!server.allowed-ip.*"
      "server.*"
      "certificate.*"
      "authentication.fallback-admin.*"
      "cluster.*"
      "storage.data"
      "storage.blob"
      "storage.lookup"
      "storage.fts"
      "storage.directory"
      "enterprise.license-key"
      "http.*"
      "cache.http-auth.*"
      "oauth.key"
      "session.auth.mechanisms.*"
      "sieve.untrusted.limits.redirects"
      "sieve.untrusted.max-redirects"
      "queue.connection.default.source-ips.*"
      "webadmin.path"
      "webadmin.resource"
      "spam-filter.resource"
      "resolver.public-suffix.*"
      "resolver.type"
    ];
    http = {
      url = "'https://${hostname}'";
      use-x-forwarded = true;
    };
    # The 0.15 HTTP cache can reuse expired credentials; introspect every request.
    cache.http-auth = {
      size = 0;
      capacity = 0;
    };
    server = {
      hostname = hostname;
      listener = {
        smtp = {
          bind = ["[::]:25"];
          protocol = "smtp";
        };
        submissions = {
          bind = ["[::]:465"];
          protocol = "smtp";
          tls.implicit = true;
        };
        imaptls = {
          bind = ["[::]:993"];
          protocol = "imap";
          tls.implicit = true;
        };
        sieve = {
          bind = ["127.0.0.1:4190"];
          protocol = "managesieve";
        };
        http = {
          bind = ["127.0.0.1:8080"];
          protocol = "http";
        };
      };
    };
    certificate.default = {
      cert.file = "/var/lib/acme/${hostname}/fullchain.pem";
      private-key.file = "/var/lib/acme/${hostname}/key.pem";
      default = true;
    };
    authentication.fallback-admin = {
      user = "admin";
      secret.file = config.sops.secrets.stalwart-admin-password.path;
    };
    oauth.key.file = config.sops.secrets.stalwart-oauth-key.path;
    # Public MX delivery must not pick up the tailnet's split DNS addresses.
    resolver.type = "cloudflare";
    queue.connection.default.source-ips = ["155.138.245.163" "2001:19f0:6401:cf2::1"];
    storage.directory = "gablogin";
    directory.gablogin = {
      type = "oidc";
      endpoint = {
        url = "http://127.0.0.1:8081/introspect";
        method = "introspect";
      };
      auth.method = "none";
      fields.email = "mail_account";
    };
    sieve.untrusted = {
      limits.redirects = 2;
      max-redirects = 2;
    };
    session.auth.mechanisms = [
      {
        "if" = "local_port != 25 && is_tls";
        "then" = "[oauthbearer, xoauth2]";
      }
      {"else" = false;}
    ];
  };
in {
  imports = [../../common/optional/nginx.nix];

  sops.secrets = {
    stalwart-admin-password.sopsFile = ../secrets.yaml;
    contato-password.sopsFile = ../secrets.yaml;
    stalwart-oauth-key.sopsFile = ../secrets.yaml;
    authentik-stalwart-client-secret.sopsFile = ../secrets.yaml;
  };

  services.stalwart = {
    enable = true;
    stateVersion = "26.05";
    credentials = lib.listToAttrs (map (file: lib.nameValuePair (credentialName file) file) files);
    settings = rewriteFiles settings;
  };

  networking.firewall.allowedTCPPorts = [25 465 993];

  # The canary needs no DNS or certificate changes in m7.rs.
  services.nginx.virtualHosts."asterope.m7.rs" = {
    enableACME = lib.mkForce false;
    forceSSL = lib.mkForce false;
  };
  services.nginx.appendHttpConfig = ''
    map $status $stalwart_auth_challenge {
      default "";
      401 'Bearer resource_metadata="https://${hostname}/.well-known/oauth-protected-resource"';
    }
  '';
  services.nginx.virtualHosts.${hostname} = {
    forceSSL = true;
    enableACME = true;
    locations = {
      "/" = {
        proxyPass = "http://127.0.0.1:8080";
        proxyWebsockets = true;
        recommendedProxySettings = false;
        extraConfig = ''
          proxy_hide_header WWW-Authenticate;
          add_header WWW-Authenticate $stalwart_auth_challenge always;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $remote_addr;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host $host;
        '';
      };
      "= /.well-known/openid-configuration".return = "302 https://auth.m7.rs/application/o/stalwart/.well-known/openid-configuration";
      "= /.well-known/oauth-authorization-server".return = "302 https://auth.m7.rs/application/o/stalwart/.well-known/openid-configuration";
      "= /.well-known/oauth-protected-resource" = {
        extraConfig = "default_type application/json;";
        return = "200 '${builtins.toJSON {
          resource = "https://${hostname}";
          authorization_servers = ["https://auth.m7.rs/application/o/stalwart/"];
          scopes_supported = ["openid" "profile" "email" "offline_access"];
          bearer_methods_supported = ["header"];
        }}'";
      };
      # Management stays on the tailnet; DAV/JMAP and OAuth remain public.
      "^~ /api/" = {
        proxyPass = "http://127.0.0.1:8080";
        extraConfig = privateAccess;
      };
    };
  };

  systemd.tmpfiles.rules = ["d /var/lib/acme/acme-challenge 0755 acme nginx -"];
  # Stalwart 0.15 maps introspection claims without checking active/client/scope.
  systemd.services.stalwart-introspection = {
    description = "Validate Gablogin mail token introspection";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${introspection}";
      LoadCredential = ["client-secret:${config.sops.secrets.authentik-stalwart-client-secret.path}"];
      DynamicUser = true;
      Restart = "on-failure";
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
    };
  };
  security.acme.certs.${hostname}.reloadServices = ["stalwart.service"];
  systemd.services.stalwart = {
    wants = ["acme-${hostname}.service" "stalwart-introspection.service"];
    after = ["acme-${hostname}.service" "stalwart-introspection.service"];
  };

  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/stalwart";
      user = "stalwart";
      group = "stalwart";
      mode = "0700";
    }
  ];
}

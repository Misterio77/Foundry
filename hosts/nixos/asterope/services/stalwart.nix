{
  config,
  lib,
  pkgs,
  ...
}: let
  hostname = "mail.lumis.cards";
  operations = import ./stalwart-plan.nix {inherit lib;};
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
    then {
      "@type" = "File";
      filePath = "/run/credentials/stalwart.service/${credentialName value.file}";
    }
    else if lib.isList value
    then map rewriteFiles value
    else if lib.isAttrs value
    then lib.mapAttrs (_: rewriteFiles) value
    else value;
  files = lib.unique (collectFiles operations);
  plan = pkgs.writeText "stalwart-plan.ndjson" (
    lib.concatMapStringsSep "\n" (operation: builtins.toJSON (rewriteFiles operation)) operations + "\n"
  );
  database = (pkgs.formats.json {}).generate "stalwart-config.json" {
    "@type" = "RocksDb";
    path = "/var/lib/stalwart/v1/db";
  };
  start = pkgs.writeShellScript "stalwart-start" ''
    export STALWART_RECOVERY_ADMIN="admin:$(<"$CREDENTIALS_DIRECTORY/admin-password")"
    exec ${lib.getExe pkgs.stalwart_1} --config=${database}
  '';
  apply = pkgs.writeShellScript "stalwart-apply" ''
    export STALWART_URL=http://127.0.0.1:8080
    export STALWART_USER=admin
    export STALWART_PASSWORD="$(<"$CREDENTIALS_DIRECTORY/admin-password")"
    for attempt in {1..60}; do
      ${lib.getExe pkgs.stalwart-cli_1} get SystemSettings --json >/dev/null 2>&1 && break
      sleep 1
    done
    ${lib.getExe pkgs.stalwart-cli_1} apply --file ${plan}
    ${lib.getExe pkgs.stalwart-cli_1} create Action/ReloadSettings --json '{}' >/dev/null
  '';
  publicJmap = pkgs.runCommand "stalwart-public-jmap.py" {nativeBuildInputs = [pkgs.python3];} ''
    cp ${./public-jmap.py} public-jmap.py
    cp ${./test_public_jmap.py} test_public_jmap.py
    python3 -B -m unittest discover -p 'test_public_jmap.py'
    cp public-jmap.py $out
  '';
  privateAccess = ''
    allow 127.0.0.1;
    allow ::1;
    allow 100.77.0.0/24;
    allow fd7a:115c:a1e0:77::/64;
    deny all;
  '';
  proxyHeaders = ''
    proxy_hide_header WWW-Authenticate;
    add_header WWW-Authenticate $stalwart_auth_challenge always;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $host;
  '';
in {
  imports = [../../common/optional/nginx.nix];

  sops.secrets.stalwart-admin-password.sopsFile = ../secrets.yaml;

  services.stalwart = {
    enable = true;
    stateVersion = "26.05";
    package = pkgs.stalwart_1;
    # The upstream module still generates 0.15 TOML; 1.0 uses JSON plus API plans.
    settings = lib.mkForce {};
    credentials =
      lib.listToAttrs (map (file: lib.nameValuePair (credentialName file) file) files)
      // {admin-password = config.sops.secrets.stalwart-admin-password.path;};
  };
  systemd.services.stalwart = {
    wants = ["acme-${hostname}.service" "stalwart-public-jmap.service"];
    after = ["acme-${hostname}.service"];
    environment = {
      STALWART_PUBLIC_URL = "https://${hostname}";
      HOME = "/var/lib/stalwart";
      XDG_CACHE_HOME = "/var/lib/stalwart/.cache";
    };
    serviceConfig = {
      Type = lib.mkForce "exec";
      ExecStart = lib.mkForce ["" start];
      ExecStartPost = [apply];
    };
    unitConfig.ConditionPathExists = lib.mkForce [database];
  };

  networking.firewall.allowedTCPPorts = [25 465 993];
  services.nginx.virtualHosts."asterope.m7.rs" = {
    enableACME = lib.mkForce false;
    forceSSL = lib.mkForce false;
  };
  services.nginx.appendHttpConfig = ''
    map $status $stalwart_auth_challenge {
      default "";
      401 'Bearer resource_metadata="https://${hostname}/.well-known/oauth-protected-resource"';
    }
    geo $stalwart_private_client {
      default 0;
      127.0.0.1 1;
      ::1 1;
      100.77.0.0/24 1;
      fd7a:115c:a1e0:77::/64 1;
    }
    map $stalwart_private_client $stalwart_jmap_backend {
      0 http://127.0.0.1:8081;
      1 http://127.0.0.1:8080;
    }
  '';
  services.nginx.virtualHosts.${hostname} = {
    forceSSL = true;
    enableACME = true;
    locations = {
      "/" = {
        proxyPass = "http://127.0.0.1:8080";
        recommendedProxySettings = false;
        extraConfig = proxyHeaders;
      };
      "= /jmap".return = "308 /jmap/";
      "= /jmap/" = {
        proxyPass = "$stalwart_jmap_backend";
        recommendedProxySettings = false;
        extraConfig = proxyHeaders;
      };
      # WebSocket messages could bypass the public JSON management filter.
      "^~ /jmap/ws" = {
        proxyPass = "http://127.0.0.1:8080";
        proxyWebsockets = true;
        extraConfig = privateAccess;
      };
      "^~ /api/" = {
        proxyPass = "http://127.0.0.1:8080";
        extraConfig = privateAccess;
      };
      "^~ /admin" = {
        proxyPass = "http://127.0.0.1:8080";
        extraConfig = privateAccess;
      };
      "= /.well-known/openid-configuration".return = "302 https://auth.m7.rs/application/o/stalwart/.well-known/openid-configuration";
      "= /.well-known/oauth-authorization-server".return = "302 https://auth.m7.rs/application/o/stalwart/.well-known/openid-configuration";
      "= /.well-known/oauth-protected-resource" = {
        extraConfig = "default_type application/json;";
        return = "200 '${builtins.toJSON {
          resource = "https://${hostname}";
          authorization_servers = ["https://auth.m7.rs/application/o/stalwart/"];
          scopes_supported = [
            "openid"
            "profile"
            "email"
            "offline_access"
            "urn:ietf:params:oauth:scope:mail"
            "urn:ietf:params:oauth:scope:calendars"
            "urn:ietf:params:oauth:scope:contacts"
          ];
          bearer_methods_supported = ["header"];
        }}'";
      };
    };
  };
  # 1.0 multiplexes management and user methods on the same JMAP endpoint.
  systemd.services.stalwart-public-jmap = {
    description = "Keep Stalwart management JMAP methods private";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${publicJmap}";
      DynamicUser = true;
      MemoryMax = "128M";
      Restart = "on-failure";
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
    };
  };
  systemd.tmpfiles.rules = ["d /var/lib/acme/acme-challenge 0755 acme nginx -"];
  security.acme.certs.${hostname}.reloadServices = ["stalwart.service"];
  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/stalwart";
      user = "stalwart";
      group = "stalwart";
      mode = "0700";
    }
  ];
}

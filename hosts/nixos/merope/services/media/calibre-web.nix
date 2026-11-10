{
  config,
  outputs,
  lib,
  pkgs,
  ...
}: let
  outpostProxy = ''
    proxy_ssl_server_name on;
    proxy_ssl_name auth.m7.rs;
    proxy_ssl_verify on;
    proxy_ssl_verify_depth 4;
    proxy_ssl_trusted_certificate ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt;
    proxy_set_header Host auth.m7.rs;
    proxy_set_header Authorization "";
  '';
in {
  users.users = {
    # Allow calibre-server to write to readarr-managed library
    calibre-server.extraGroups = [config.services.readarr.group];
  };

  services = {
    calibre-server = {
      enable = true;
      package = pkgs.calibre.override {speechSupport = false;};
      libraries = ["/srv/media/books"];
      auth.enable = true;
      # Readarr connects locally
      extraFlags = ["--enable-local-write"];
    };

    calibre-web = {
      enable = true;
      listen.ip = "127.0.0.1";
      options.calibreLibrary = lib.head config.services.calibre-server.libraries;
    };

    nginx.virtualHosts = {
      "books.m7.rs" = {
        forceSSL = true;
        enableACME = true;
        locations = {
          "/" = {
            proxyPass = "http://127.0.0.1:${toString config.services.calibre-web.listen.port}";
            recommendedProxySettings = false;
            extraConfig = ''
              auth_request /_calibre-web_auth;
              error_page 401 = @calibre-web_login;
              auth_request_set $calibre_web_subject $upstream_http_x_foundry_calibre_web_subject;
              auth_request_set $calibre_web_username $upstream_http_x_foundry_calibre_web_username;
              auth_request_set $calibre_web_email $upstream_http_x_foundry_calibre_web_email;
              auth_request_set $calibre_web_cookie $upstream_http_set_cookie;
              add_header Set-Cookie $calibre_web_cookie always;
              proxy_set_header Host books.m7.rs;
              proxy_set_header X-Forwarded-Host books.m7.rs;
              proxy_set_header X-Forwarded-Proto https;
              proxy_set_header X-Scheme https;
              proxy_set_header X-Forwarded-For $remote_addr;
              proxy_set_header X-Foundry-Calibre-Web-Subject $calibre_web_subject;
              proxy_set_header X-Foundry-Calibre-Web-Username $calibre_web_username;
              proxy_set_header X-Foundry-Calibre-Web-Email $calibre_web_email;
              proxy_set_header Authorization "";
              proxy_set_header X-Script-Name "";
            '';
          };
          "= /_calibre-web_auth" = {
            proxyPass = "https://auth.m7.rs/calibre-web-outpost/auth/nginx";
            recommendedProxySettings = false;
            extraConfig =
              outpostProxy
              + ''
                internal;
                proxy_pass_request_body off;
                proxy_set_header Content-Length "";
              '';
          };
          "^~ /outpost.goauthentik.io/" = {
            proxyPass = "https://auth.m7.rs/calibre-web-outpost/";
            recommendedProxySettings = false;
            extraConfig = outpostProxy;
          };
          "@calibre-web_login".extraConfig = ''
            add_header Set-Cookie $calibre_web_cookie always;
            return 302 /outpost.goauthentik.io/start?rd=https://books.m7.rs/;
          '';
          "= /opds".return = "404";
          "^~ /opds/".return = "404";
          "= /kobo".return = "404";
          "^~ /kobo/".return = "404";
        };
      };
      "calibre.m7.rs" = {
        forceSSL = true;
        enableACME = true;
        extraConfig = ''
          allow 127.0.0.1;
          allow ::1;
          allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v4};
          allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v6};
          deny all;
        '';
        locations."/" = {
          proxyPass = "http://localhost:${toString config.services.calibre-server.port}";
          proxyWebsockets = true;
        };
      };
    };
  };

  systemd.services = {
    calibre-server = {
      bindsTo = ["srv-media.mount"];
      after = ["srv-media.mount"];
      unitConfig.ConditionPathIsMountPoint = "/srv/media";
      serviceConfig = {
        CPUWeight = 50;
        IOWeight = 50;
        UMask = "0002";
      };
    };

    calibre-web = {
      environment.FOUNDRY_PROXY_ACCOUNTS = "1";
      bindsTo = ["srv-media.mount"];
      after = ["srv-media.mount"];
      unitConfig.ConditionPathIsMountPoint = "/srv/media";
      serviceConfig = {
        CPUWeight = 50;
        IOWeight = 50;
        ReadWritePaths = lib.mkForce ["/var/lib/calibre-web"];
        ReadOnlyPaths = config.services.calibre-server.libraries;
      };
    };
  };

  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/calibre-web";
      user = config.services.calibre-web.user;
      group = config.services.calibre-web.group;
      mode = "0700";
    }
    {
      directory = "/var/lib/calibre-server";
      user = config.services.calibre-server.user;
      group = config.services.calibre-server.group;
      mode = "0700";
    }
  ];
}

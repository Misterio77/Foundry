{config, ...}: let
  port = "5232";
in {
  services = {
    radicale = {
      enable = true;
      settings = {
        server = {
          hosts = [
            "127.0.0.1:${port}"
            "::1:${port}"
          ];
        };
        auth.type = "http_x_remote_user";
        rights.type = "owner_only";
        web.prefer_browser_login = true;
        storage = {
          filesystem_folder = "/var/lib/radicale/collections";
        };
      };
    };
    nginx.appendHttpConfig = ''
      map $http_authorization $dav_request_cookie {
        default "";
        "" $http_cookie;
      }
      map $http_authorization $dav_outpost_cookie {
        default "";
        "" $upstream_http_set_cookie;
      }
      map "$request_method:$http_accept" $dav_browser_navigation {
        default 0;
        ~*^(GET|HEAD):.*text/html 1;
      }
    '';
    nginx.virtualHosts = {
      "dav.m7.rs" = {
        forceSSL = true;
        enableACME = true;
        locations = {
          "/" = {
            proxyPass = "http://localhost:${port}";
            recommendedProxySettings = false;
            extraConfig = ''
              auth_request /_dav_auth;
              error_page 401 = @dav_unauthorized;

              auth_request_set $dav_principal $upstream_http_x_foundry_dav_principal;
              auth_request_set $dav_set_cookie $dav_outpost_cookie;
              add_header Set-Cookie $dav_set_cookie always;
              proxy_set_header X-Remote-User $dav_principal;
              proxy_set_header Authorization "";
              proxy_set_header Cookie "";
              proxy_set_header Host $host;
              proxy_set_header X-Script-Name "";
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-For $remote_addr;
            '';
          };
          "= /_dav_auth" = {
            proxyPass = "http://127.0.0.1:9000/outpost.goauthentik.io/auth/nginx";
            recommendedProxySettings = false;
            extraConfig = ''
              internal;
              proxy_pass_request_body off;
              proxy_set_header Content-Length "";
              proxy_set_header Host dav.m7.rs;
              # A fixed URL avoids the outpost's reserved-path authentication bypass.
              proxy_set_header X-Original-URL https://dav.m7.rs/;
              proxy_set_header X-Forwarded-Host dav.m7.rs;
              proxy_set_header X-Forwarded-Proto https;
              proxy_set_header X-Forwarded-For $remote_addr;
              proxy_set_header Authorization $http_authorization;
              # The outpost checks cookies first; explicit credentials must stand alone.
              proxy_set_header Cookie $dav_request_cookie;
              proxy_intercept_errors on;
              # DAV clients need an authentication challenge, never a browser redirect.
              error_page 301 302 303 307 308 = @dav_unauthorized;
            '';
          };
          "^~ /outpost.goauthentik.io/" = {
            proxyPass = "http://127.0.0.1:9000";
            recommendedProxySettings = false;
            extraConfig = ''
              proxy_set_header Host dav.m7.rs;
              proxy_set_header X-Original-URL https://dav.m7.rs/;
              proxy_set_header X-Forwarded-Host dav.m7.rs;
              proxy_set_header X-Forwarded-Proto https;
              proxy_set_header X-Forwarded-For $remote_addr;
              proxy_set_header Authorization $http_authorization;
              proxy_set_header Cookie $dav_request_cookie;
              # Header authentication must not mint a reusable browser session.
              proxy_hide_header Set-Cookie;
              add_header Set-Cookie $dav_outpost_cookie always;
            '';
          };
          "@dav_unauthorized".extraConfig = ''
            add_header Set-Cookie $dav_set_cookie always;
            if ($http_authorization != "") {
              return 401;
            }
            if ($dav_browser_navigation) {
              return 302 /outpost.goauthentik.io/start?rd=https://dav.m7.rs/.web/;
            }
            add_header WWW-Authenticate 'Basic realm="Gablogin DAV"' always;
            add_header WWW-Authenticate 'Bearer realm="Gablogin DAV"' always;
            return 401;
          '';
        };
        extraConfig = ''
          allow 127.0.0.1;
          allow ::1;
          allow ${config.services.headscale.settings.prefixes.v4};
          allow ${config.services.headscale.settings.prefixes.v6};
          deny all;
        '';
      };
    };
  };
  services.borgbackup.jobs.alcyone.paths = [config.services.radicale.settings.storage.filesystem_folder];

  environment.persistence = {
    "/persist".directories = [
      {
        directory = "/var/lib/radicale";
        user = config.users.users.radicale.name;
        group = config.users.users.radicale.group;
        mode = "0755";
      }
    ];
  };
}

{
  config,
  lib,
  pkgs,
  ...
}: let
  socket = config.services.radicale.unixSocket.path;
in {
  sops.secrets.authentik-radicale-directory-token = {
    sopsFile = ../secrets.yaml;
    restartUnits = ["radicale.service"];
  };
  systemd.services.radicale.serviceConfig = {
    # The sharing directory needs Authentik, beyond the upstream module's localhost-only egress.
    IPAddressAllow = lib.mkForce [];
    IPAddressDeny = lib.mkForce [];
    LoadCredential = [
      "authentik-directory-token:${config.sops.secrets.authentik-radicale-directory-token.path}"
    ];
  };

  services = {
    radicale = {
      enable = true;
      unixSocket = {
        enable = true;
        group = config.services.nginx.group;
      };
      settings = {
        auth.type = "http_x_remote_user";
        rights.type = "owner_only";
        sharing = {
          type = "files";
          database_path = "${config.services.radicale.settings.storage.filesystem_folder}/collection-db/files";
          collection_by_map = true;
          permit_create_map = true;
          collection_by_token = false;
          permit_create_token = false;
          default_permissions_create_map = "r";
        };
        web = {
          type = "internal";
          prefer_browser_login = true;
          authentik_api_url = "https://auth.m7.rs/api/v3/";
          authentik_token_file = "/run/credentials/radicale.service/authentik-directory-token";
        };
        storage = {
          filesystem_folder = "/var/lib/radicale/collections";
        };
      };
    };
    nginx.additionalModules = [pkgs.nginxModules.moreheaders];
    nginx.appendHttpConfig = ''
      map $http_authorization $dav_request_cookie {
        default "";
        "" $http_cookie;
      }
      map $http_authorization $dav_outpost_cookie {
        default "";
        "" $upstream_http_set_cookie;
      }
      # The sharing API accepts form POSTs; cookies alone are not CSRF protection.
      map "$request_method:$http_origin" $dav_cookie_write_allowed {
        default 0;
        ~^(GET|HEAD|OPTIONS): 1;
        "~^[A-Z]+:https://dav\\.m7\\.rs$" 1;
      }
      map "$dav_cookie_write_allowed:$http_authorization:$http_cookie" $dav_reject_cookie_write {
        default 0;
        ~^0::.+$ 1;
      }
      # This marker only changes the challenge, never authentication or CSRF checks.
      map "$http_x_radicale_web:$dav_browser_navigation" $dav_challenge {
        default 'Basic realm="Gablogin DAV", Bearer realm="Gablogin DAV"';
        ~^(1:|.*:1$) "";
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
            proxyPass = "http://unix:${socket}:";
            recommendedProxySettings = false;
            extraConfig = ''
              if ($dav_reject_cookie_write) {
                return 403;
              }
              auth_request /_dav_auth;
              error_page 401 = @dav_unauthorized;

              auth_request_set $dav_principal $upstream_http_x_foundry_dav_principal;
              auth_request_set $dav_username $upstream_http_x_foundry_dav_username;
              auth_request_set $dav_set_cookie $dav_outpost_cookie;
              add_header Set-Cookie $dav_set_cookie always;
              proxy_set_header X-Remote-User $dav_principal;
              proxy_set_header X-Foundry-DAV-Username $dav_username;
              proxy_set_header Authorization "";
              proxy_set_header Cookie "";
              proxy_set_header Host dav.m7.rs;
              proxy_set_header X-Forwarded-Host dav.m7.rs;
              proxy_set_header X-Forwarded-Port 443;
              proxy_set_header X-Script-Name "";
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-For $remote_addr;
            '';
          };
          "= /.sharing-users" = {
            proxyPass = "http://unix:${socket}:";
            recommendedProxySettings = false;
            extraConfig = ''
              if ($request_method != GET) {
                return 405;
              }
              auth_request /_dav_auth;
              error_page 401 = @dav_unauthorized;
              auth_request_set $dav_directory_principal $upstream_http_x_foundry_dav_principal;
              auth_request_set $dav_directory_username $upstream_http_x_foundry_dav_username;
              auth_request_set $dav_directory_cookie $dav_outpost_cookie;
              add_header Set-Cookie $dav_directory_cookie always;
              proxy_pass_request_body off;
              proxy_set_header Content-Length "";
              proxy_set_header Authorization "";
              proxy_set_header Cookie "";
              proxy_set_header Host dav.m7.rs;
              proxy_set_header X-Forwarded-For $remote_addr;
              proxy_set_header X-Forwarded-Proto https;
              proxy_set_header X-Remote-User $dav_directory_principal;
              proxy_set_header X-Foundry-DAV-Username $dav_directory_username;
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
            # auth_request copies the outpost challenge even through error_page.
            more_set_headers 'WWW-Authenticate: $dav_challenge';
            add_header Set-Cookie $dav_set_cookie always;
            if ($http_authorization != "") {
              return 401;
            }
            if ($dav_browser_navigation) {
              return 302 /outpost.goauthentik.io/start?rd=https://dav.m7.rs/.web/;
            }
            return 401;
          '';
        };
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

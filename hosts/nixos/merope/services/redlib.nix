{
  config,
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
  services.redlib = {
    enable = true;
    address = "127.0.0.1";
  };

  services.nginx.virtualHosts."redlib.m7.rs" = {
    forceSSL = true;
    enableACME = true;
    locations = {
      "/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.redlib.port}";
        recommendedProxySettings = false;
        extraConfig = ''
          auth_request /_redlib_auth;
          error_page 401 = @redlib_login;
          # A location-level error_page disables all server-level inheritance.
          error_page 502 503 504 /__nginx_unavailable.html;
          auth_request_set $redlib_cookie $upstream_http_set_cookie;
          add_header Set-Cookie $redlib_cookie always;
          proxy_set_header Host redlib.m7.rs;
          proxy_set_header X-Forwarded-Host redlib.m7.rs;
          proxy_set_header X-Forwarded-Proto https;
          proxy_set_header X-Forwarded-For $remote_addr;
          proxy_set_header Authorization "";
        '';
      };
      "= /_redlib_auth" = {
        proxyPass = "https://auth.m7.rs/redlib-outpost/auth/nginx";
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
        proxyPass = "https://auth.m7.rs/redlib-outpost/";
        recommendedProxySettings = false;
        extraConfig = outpostProxy;
      };
      "@redlib_login".extraConfig = ''
        add_header Set-Cookie $redlib_cookie always;
        return 302 /outpost.goauthentik.io/start?rd=https://redlib.m7.rs/;
      '';
    };
  };
}

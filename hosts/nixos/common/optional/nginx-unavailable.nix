{lib, ...}: {
  options.services.nginx.virtualHosts = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      config = {
        # Keep application error bodies (and API responses) intact; only nginx's
        # own gateway failures use this page unless a service opts into interception.
        extraConfig = lib.mkAfter ''
          error_page 502 503 504 /__nginx_unavailable.html;
        '';
        locations."= /__nginx_unavailable.html" = {
          alias = ./nginx-unavailable.html;
          extraConfig = ''
            internal;
            default_type text/html;
            charset utf-8;
            add_header Cache-Control "no-store" always;
            add_header Retry-After "10" always;
          '';
        };
      };
    });
  };
}

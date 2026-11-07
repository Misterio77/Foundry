{config, ...}: let
  port = config.services.robohash.port;
in {
  # Keep transient DNS failures from triggering Authentik's eight-hour avatar failure cache.
  networking.hosts."127.0.0.2" = ["avatars.m7.rs"];

  services.robohash.enable = true;

  services.nginx = {
    validateConfigFile = true;
    proxyCachePath."avatars" = {
      enable = true;
      keysZoneName = "avatars";
      keysZoneSize = "1m";
      maxSize = "100m";
      inactive = "365d";
    };
    virtualHosts."avatars.m7.rs" = {
      forceSSL = true;
      enableACME = true;
      locations."~ \"^/[^/]+\\.png$\"" = {
        proxyPass = "http://127.0.0.1:${toString port}";
        extraConfig = ''
          # Fix generation parameters to bound CPU/memory use and disable remote Gravatar lookups.
          set $args "set=set4&size=200x200";
          proxy_cache avatars;
          proxy_cache_key $uri;
          proxy_cache_valid 200 365d;
          proxy_cache_lock on;
          proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
          add_header Access-Control-Allow-Origin "*" always;
        '';
      };
      locations."/".return = "404";
    };
  };
}

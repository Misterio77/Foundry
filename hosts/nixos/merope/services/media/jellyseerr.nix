{
  config,
  pkgs,
  ...
}: {
  services.seerr = {
    enable = true;
    package = pkgs.seerr-oidc;
    declarative = {
      enable = true;
      owner = {
        provider = "authentik";
        subject = "f7201636157b4b425c99d1c165e6840fb23dc59d18c83384658803a90189475f";
        email = "akadmin@m7.rs";
        username = "akadmin";
      };
      settings = {
        main.applicationUrl = "https://requests.m7.rs";
        oidc.providers = [
          {
            slug = "authentik";
            name = "Gablogin";
            issuerUrl = "https://auth.m7.rs/application/o/seerr/";
            clientId = "seerr";
            clientSecret.file = config.sops.secrets.authentik-seerr-client-secret.path;
            scopes = "openid profile email seerr_permissions";
            permissionsClaim = "seerr_permissions";
            newUserLogin = true;
            logoutMode = "provider";
            backchannelLogout = true;
          }
        ];
        jellyfin = {
          name = "merope";
          ip = "media.m7.rs";
          port = 443;
          useSsl = true;
          serverId = "5c9da3c6fa2e4ec580b6b6dc42b666d8";
          apiKey.file = config.sops.secrets.jellyfin-key.path;
          libraries = [
            {
              id = "f137a2dd21bbc1b99aa5c0f6bf02a805";
              name = "Movies";
              enabled = true;
              type = "movie";
            }
            {
              id = "a656b907eb3a73532e40e44b968d0225";
              name = "Shows";
              enabled = true;
              type = "show";
            }
          ];
        };
        radarr = [
          {
            id = 1;
            name = "Radarr";
            externalUrl = "https://radarr.m7.rs";
            hostname = "localhost";
            port = config.services.radarr.settings.server.port;
            apiKey.file = config.sops.secrets.radarr-key.path;
            activeProfileId = 11;
            activeProfileName = "HD Bluray + WEB";
            activeDirectory = "/srv/media/movies";
            isDefault = true;
          }
        ];
        sonarr = [
          {
            id = 1;
            name = "Sonarr";
            externalUrl = "https://sonarr.m7.rs";
            hostname = "localhost";
            port = config.services.sonarr.settings.server.port;
            apiKey.file = config.sops.secrets.sonarr-key.path;
            activeProfileId = 7;
            activeProfileName = "WEB-1080p";
            activeDirectory = "/srv/media/tv";
            activeAnimeProfileId = 8;
            activeAnimeProfileName = "Remux-1080p - Anime";
            activeAnimeDirectory = "/srv/media/tv";
            isDefault = true;
          }
        ];
      };
    };
  };

  sops.secrets = {
    radarr-key.restartUnits = ["seerr.service"];
    sonarr-key.restartUnits = ["seerr.service"];
    authentik-seerr-client-secret = {
      sopsFile = ../../secrets.yaml;
      restartUnits = ["seerr.service"];
    };
    jellyfin-key = {
      sopsFile = ../../secrets.yaml;
      restartUnits = ["seerr.service"];
    };
  };

  services.nginx.virtualHosts."requests.m7.rs" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://localhost:${toString config.services.seerr.port}";
      proxyWebsockets = true;
    };
  };

  environment.persistence."/persist".directories = [
    "/var/lib/private/jellyseerr"
  ];
}

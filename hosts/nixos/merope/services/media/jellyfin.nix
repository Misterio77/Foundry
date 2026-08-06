{config, lib, ...}: {
  # https://jellyfin.org/docs/general/post-install/networking/
  # TODO: https://github.com/Sveske-Juice/declarative-jellyfin
  options.services.jellyfin.port = lib.mkOption { default = 8096; type = lib.types.port; };

  config = {
    services = {
      jellyfin = {
        enable = true;
      };
      nginx.virtualHosts = {
        "media.m7.rs" = {
          forceSSL = true;
          enableACME = true;
          locations."/" = {
            proxyPass = "http://localhost:${toString config.services.jellyfin.port}";
            proxyWebsockets = true;
          };
        };
        "music.m7.rs" = {
          forceSSL = true;
          enableACME = true;
          locations."/".return = "302 https://media.m7.rs/web/#/music.html";
        };
        "music.misterio.me" = {
          forceSSL = true;
          enableACME = true;
          locations."/".return = "302 https://media.m7.rs/web/#/music.html";
        };
      };
    };

    # Make config readable by jellyfin group (e.g. jellysearch)
    systemd = {
      tmpfiles.settings.jellyfinDirs = {
        "${config.services.jellyfin.dataDir}".d.mode = lib.mkForce "750";
      };
      services.jellyfin.serviceConfig.UMask = lib.mkForce "0027";
    };

    environment.persistence = {
      "/persist".directories = [
        {
          directory = "/var/lib/jellyfin";
          user = config.services.jellyfin.user;
          group = config.services.jellyfin.group;
          mode = "0700";
        }
      ];
    };
  };
}

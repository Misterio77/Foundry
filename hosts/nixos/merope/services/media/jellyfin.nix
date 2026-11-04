{
  config,
  lib,
  outputs,
  ...
}: {
  # https://jellyfin.org/docs/general/post-install/networking/
  # TODO: https://github.com/Sveske-Juice/declarative-jellyfin
  options.services.jellyfin.port = lib.mkOption {
    default = 8096;
    type = lib.types.port;
  };

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
          # ASP.NET routes are case-insensitive; cover /Metrics too.
          locations."~* ^/metrics(?:/|$)" = {
            proxyPass = "http://localhost:${toString config.services.jellyfin.port}";
            extraConfig = ''
              allow 127.0.0.1;
              allow ::1;
              allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v4};
              allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v6};
              deny all;
            '';
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

    # Make config readable by the jellyfin group
    systemd = {
      tmpfiles.settings.jellyfinDirs = {
        "${config.services.jellyfin.dataDir}".d.mode = lib.mkForce "750";
      };
      services.jellyfin = {
        bindsTo = ["srv-media.mount"];
        after = ["srv-media.mount"];
        unitConfig.ConditionPathIsMountPoint = "/srv/media";
        serviceConfig.UMask = lib.mkForce "0027";
      };
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

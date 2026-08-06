{config, outputs, ...}: {
  services.immich = {
    enable = true;
    accelerationDevices = ["/dev/dri/renderD128"];
    mediaLocation = "/srv/media/photos";
    settings = {
      server.externalDomain = "https://photos.m7.rs";
    };
  };
  services.immich-public-proxy = {
    enable = true;
    immichUrl = "http://localhost:${toString config.services.immich.port}";
  };

  services.nginx.virtualHosts."photos.m7.rs" = {
    forceSSL = true;
    enableACME = true;
    locations = {
      "/" = {
        proxyPass = "http://localhost:${toString config.services.immich.port}";
        proxyWebsockets = true;
        extraConfig = ''
          allow 127.0.0.1;
          allow ::1;
          allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v4};
          allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v6};
          deny all;

          # https://docs.immich.app/administration/reverse-proxy
          client_max_body_size 50000M;
          proxy_request_buffering off;
          client_body_buffer_size 1024k;
          proxy_read_timeout 600s;
          proxy_send_timeout 600s;
          send_timeout 600s;
        '';
      };
      "/share" = {
        proxyPass = "http://localhost:${toString config.services.immich-public-proxy.port}";
      };
    };
  };

  /*
  No need for this if mediaLocation is in a non ephemeral mountpoint
  environment.persistence = {
    "/persist".directories = [
      {
        directory = config.services.immich.mediaLocation;
        user = config.services.immich.user;
        group = config.services.immich.group;
        mode = "0700";
      }
    ];
  };
  */

  systemd.tmpfiles.settings.srv-media-photos."/srv/media/photos".d = {
    user = config.services.immich.user;
    group = config.services.immich.group;
    mode = "0750";
  };
}

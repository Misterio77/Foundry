{
  config,
  outputs,
  lib,
  ...
}: {
  users.users = {
    # Allow calibre-server to write to readarr-managed library
    calibre-server.extraGroups = [config.services.readarr.group];
  };

  services = {
    calibre-server = {
      enable = true;
      libraries = ["/srv/media/books"];
      auth.enable = true;
      # Readarr connects locally
      extraFlags = ["--enable-local-write"];
    };

    calibre-web = {
      enable = true;
      options.calibreLibrary = lib.head config.services.calibre-server.libraries;
    };

    nginx.virtualHosts = {
      "books.m7.rs" = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://localhost:${toString config.services.calibre-web.listen.port}";
          proxyWebsockets = true;
        };
      };
      "calibre.m7.rs" = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://localhost:${toString config.services.calibre-server.port}";
          proxyWebsockets = true;
          extraConfig = ''
            allow 127.0.0.1;
            allow ::1;
            allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v4};
            allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v6};
            deny all;
          '';
        };
      };
    };
  };

  systemd.services = {
    calibre-server.serviceConfig = {
      CPUWeight = 50;
      IOWeight = 50;
      UMask = "0002";
    };

    calibre-web.serviceConfig = {
      CPUWeight = 50;
      IOWeight = 50;
      ReadWritePaths = lib.mkForce ["/var/lib/calibre-web"];
      ReadOnlyPaths = config.services.calibre-server.libraries;
    };
  };

  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/calibre-web";
      user = config.services.calibre-web.user;
      group = config.services.calibre-web.group;
      mode = "0700";
    }
  ];
}

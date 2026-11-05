{
  config,
  outputs,
  ...
}: {
  sops.secrets.authentik-immich-client-secret = {
    sopsFile = ../secrets.yaml;
    restartUnits = ["immich-server.service"];
  };

  services.immich = {
    enable = true;
    accelerationDevices = ["/dev/dri/renderD128"];
    mediaLocation = "/srv/media/photos";
    settings = {
      server.externalDomain = "https://photos.m7.rs";
      passwordLogin.enabled = false;
      oauth = {
        enabled = true;
        issuerUrl = "https://auth.m7.rs/application/o/immich/";
        clientId = "immich";
        clientSecret._secret = config.sops.secrets.authentik-immich-client-secret.path;
        scope = "openid email profile immich_roles immich_quota";
        roleClaim = "immich_role";
        storageQuotaClaim = "immich_quota";
        signingAlgorithm = "RS256";
        buttonText = "Entrar com Gablogin";
        autoLaunch = true;
        # Good to keep an eye in https://github.com/immich-app/immich/discussions/32542
        accountManagementUrl = "https://auth.m7.rs/if/user/#/settings";
        autoRegister = true;
        mobileOverrideEnabled = false;
      };
    };
  };
  services.immich-public-proxy = {
    enable = true;
    immichUrl = "http://localhost:${toString config.services.immich.port}";
  };

  services.nginx.virtualHosts."photos.m7.rs" = {
    forceSSL = true;
    enableACME = true;
    extraConfig = ''
      allow 127.0.0.1;
      allow ::1;
      allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v4};
      allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v6};
      deny all;
    '';
    locations = {
      "/" = {
        proxyPass = "http://localhost:${toString config.services.immich.port}";
        proxyWebsockets = true;
        extraConfig = ''
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
        extraConfig = "allow all;";
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

  systemd = {
    services.immich-server = {
      bindsTo = ["srv-media.mount"];
      after = ["srv-media.mount"];
      unitConfig.ConditionPathIsMountPoint = "/srv/media";
    };

    tmpfiles.settings.srv-media-photos."/srv/media/photos".d = {
      user = config.services.immich.user;
      group = config.services.immich.group;
      mode = "0750";
    };
  };
}

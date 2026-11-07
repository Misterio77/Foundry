{
  config,
  lib,
  pkgs,
  ...
}: let
  jf = config.services.jellyfin;
  port = 8096;
  pluginDir = "${jf.dataDir}/plugins/Foundry-OIDC";
  pluginConfig = pkgs.replaceVars ./oidc.xml.in {
    clientSecretFile = config.sops.secrets.authentik-jellyfin-client-secret.path;
  };
in {
  # https://jellyfin.org/docs/general/post-install/networking/
  # TODO: https://github.com/Sveske-Juice/declarative-jellyfin
  services = {
    jellyfin = {
      enable = true;
      package = pkgs.jellyfin.override {jellyfin-web = pkgs.jellyfin-web-foundry;};
    };
    nginx.virtualHosts = {
      "media.m7.rs" = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://localhost:${toString port}";
          proxyWebsockets = true;
          recommendedProxySettings = false;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $remote_addr;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
          '';
        };
        locations."= /connect".return = "302 /sso/OIDC/QuickConnect/authentik$is_args$args";
        # ASP.NET routes are case-insensitive; cover /Metrics too.
        locations."~* ^/metrics(?:/|$)" = {
          proxyPass = "http://localhost:${toString port}";
          extraConfig = ''
            if ($ssl_client_verify != SUCCESS) {
              return 403;
            }
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

  sops.secrets.authentik-jellyfin-client-secret = {
    sopsFile = ../../../secrets.yaml;
    owner = jf.user;
    restartUnits = ["jellyfin.service"];
  };

  # Make config readable by the jellyfin group.
  systemd = {
    tmpfiles.settings.jellyfinDirs = {
      "${jf.dataDir}".d.mode = lib.mkForce "750";
    };
    services.jellyfin = {
      bindsTo = ["srv-media.mount"];
      after = ["srv-media.mount"];
      unitConfig.ConditionPathIsMountPoint = "/srv/media";
      serviceConfig.UMask = lib.mkForce "0027";
      preStart = lib.mkAfter ''
        ${pkgs.python3}/bin/python3 ${./prepare.py} ${lib.escapeShellArgs [jf.dataDir jf.configDir "${./login.html}" "${./custom.css}"]}
        install -d -m 750 ${lib.escapeShellArg pluginDir} ${lib.escapeShellArg "${jf.dataDir}/plugins/configurations"}
        install -m 640 ${pkgs.jellyfin-oidc}/*.dll ${pkgs.jellyfin-oidc}/meta.json ${lib.escapeShellArg pluginDir}/
        install -m 640 ${pluginConfig} ${lib.escapeShellArg "${jf.dataDir}/plugins/configurations/Jellyfin.Plugin.OIDC.xml"}
      '';
    };
  };

  environment.persistence = {
    "/persist".directories = [
      {
        directory = "/var/lib/jellyfin";
        user = jf.user;
        group = jf.group;
        mode = "0700";
      }
    ];
  };
}

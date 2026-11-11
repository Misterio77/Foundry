{
  lib,
  pkgs,
  ...
}: let
  domain = "screenshare.m7.rs";
  port = 3000;
in {
  systemd.services.screenshare = {
    description = "Screen sharing signaling server";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];
    environment = {
      HOST = "127.0.0.1";
      PORT = toString port;
      PUBLIC_ORIGIN = "https://${domain}";
      NODE_ENV = "production";
    };
    serviceConfig = {
      ExecStart = lib.getExe pkgs.screenshare-server;
      DynamicUser = true;
      PrivateTmp = true;
      ProtectHome = true;
      NoNewPrivileges = true;
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
    };
  };
}

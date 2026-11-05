{
  config,
  pkgs,
  ...
}: {
  services.seerr = {
    enable = true;
    package = pkgs.seerr-oidc;
  };

  sops.secrets.authentik-seerr-client-secret = {
    sopsFile = ../../secrets.yaml;
    restartUnits = ["seerr.service"];
  };

  systemd.services.seerr = {
    serviceConfig.LoadCredential = ["oidc-secret:${config.sops.secrets.authentik-seerr-client-secret.path}"];
    preStart = ''
      umask 077
      settings=${config.services.seerr.configDir}/settings.json
      mkdir -p "$(dirname "$settings")"
      test -e "$settings" || printf '{}' > "$settings"
      ${pkgs.jq}/bin/jq --rawfile secret "$CREDENTIALS_DIRECTORY/oidc-secret" '
        .main.applicationUrl = "https://requests.m7.rs"
        | .main.oidcLogin = true
        | .main.localLogin = false
        | .main.mediaServerLogin = false
        | .oidc.providers = [{
            slug: "authentik",
            name: "Gablogin",
            issuerUrl: "https://auth.m7.rs/application/o/seerr/",
            clientId: "seerr",
            clientSecret: ($secret | rtrimstr("\n")),
            scopes: "openid profile email seerr_permissions",
            permissionsClaim: "seerr_permissions",
            newUserLogin: true
          }]
      ' "$settings" > "$settings.tmp"
      mv "$settings.tmp" "$settings";
    '';
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

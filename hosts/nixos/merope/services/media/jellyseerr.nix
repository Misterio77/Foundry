{config, pkgs, ...}: let
  seerrng = pkgs.seerr.overrideAttrs (finalAttrs: previousAttrs: {
    pname = "seerrng";
    version = "3.12.3";
    src = pkgs.fetchFromGitHub {
      owner = "snapetech";
      repo = "seerrng";
      tag = "v${finalAttrs.version}";
      hash = "sha256-sX4V/9OXrwKckd5RMHvJrkoSpehtHEEHYNg267oBzVk=";
    };
    pnpmDeps = pkgs.fetchPnpmDeps {
      inherit (finalAttrs) pname version src;
      pnpm = pkgs.pnpm_10.override {nodejs-slim = pkgs.nodejs-slim_22;};
      fetcherVersion = 3;
      hash = "sha256-xd+FrZDzUA/jLkWRrlL6K9r85/nNkYDR4jF/pObXomo=";
    };
    meta =
      previousAttrs.meta
      // {
        description = "Seerr fork with music, ebook, and audiobook support";
        homepage = "https://github.com/snapetech/seerrng";
      };
  });
in {
  services.jellyseerr = {
    enable = true;
    package = seerrng;
  };

  services.nginx.virtualHosts."requests.m7.rs" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://localhost:${toString config.services.jellyseerr.port}";
      proxyWebsockets = true;
    };
  };

  environment.persistence."/persist".directories = [
    "/var/lib/private/jellyseerr"
  ];
}

{
  config,
  inputs,
  ...
}: {
  imports = [inputs.authentik-nix.nixosModules.default];

  sops.secrets.authentik-ldap-outpost-token.sopsFile = ../secrets.yaml;
  sops.templates.authentik-ldap-env = {
    content = ''
      AUTHENTIK_TOKEN=${config.sops.placeholder.authentik-ldap-outpost-token}
    '';
    restartUnits = ["authentik-ldap.service"];
  };

  services.authentik-ldap = {
    enable = true;
    environmentFile = config.sops.templates.authentik-ldap-env.path;
    listenMetrics = "127.0.0.1:9302";
  };
  systemd.services.authentik-ldap = {
    environment = {
      AUTHENTIK_HOST = "https://auth.m7.rs";
      AUTHENTIK_INSECURE = "false";
      # LDAP credentials never leave this host; the outpost uses HTTPS upstream.
      AUTHENTIK_LISTEN__LDAP = "127.0.0.1:3389";
      AUTHENTIK_LISTEN__LDAPS = "127.0.0.1:6636";
    };
    serviceConfig = {
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };
}

{
  lib,
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [inputs.nixos-mailserver.nixosModules.mailserver];

  mailserver = rec {
    stateVersion = 3;
    enable = true;
    fqdn = "mail.m7.rs";
    sendingFqdn = "alcyone.m7.rs";
    domains = [
      "m7.rs"
      "misterio.me"
      "gsfontes.com"
      "lumis.cards"
    ];
    forwards = {
      "contato@lumis.cards" = [
        "gabriel@gsfontes.com"
        "offrakki@gmail.com"
      ];
    };
    storage = {
      directoryLayout = "fs";
      path = "/srv/mail/vmail";
    };
    dkim = {
      enable = true;
      keyDirectory = "/srv/mail/dkim";
    };
    x509.useACMEHost = config.mailserver.fqdn;
    localDnsResolver = false;
    accounts = {
      "hi@m7.rs" = {
        # mkpasswd -sm bcrypt
        hashedPasswordFile = config.sops.secrets.gabriel-mail-password.path;
        aliases = map (d: "@" + d) domains;
      };
      "grafana@m7.rs" = lib.mkIf config.services.grafana.enable {
        sendOnly = true;
        hashedPasswordFile = config.sops.secrets.grafana-mail-password-hashed.path;
      };
      "media@m7.rs" = {
        sendOnly = true;
        hashedPasswordFile = config.sops.secrets.media-mail-password-hashed.path;
      };
      "firefly@m7.rs" = {
        sendOnly = true;
        hashedPasswordFile = config.sops.secrets.firefly-mail-password-hashed.path;
      };
      "calibre@m7.rs" = {
        sendOnly = true;
        hashedPasswordFile = config.sops.secrets.calibre-mail-password-hashed.path;
      };
      "contato@lumis.cards" = {
        hashedPasswordFile = config.sops.secrets.lumis-mail-password-hashed.path;
      };
    };
    mailboxes = {
      Archive = {
        auto = "subscribe";
        special_use = "\\Archive";
      };
      Drafts = {
        auto = "subscribe";
        special_use = "\\Drafts";
      };
      Sent = {
        auto = "subscribe";
        special_use = "\\Sent";
      };
      Junk = {
        auto = "subscribe";
        special_use = "\\Junk";
      };
      Trash = {
        auto = "subscribe";
        special_use = "\\Trash";
      };
    };
  };

  # Disable default open ports, we want to lock down SMTP and IMAP to tailscale.
  mailserver.openFirewall = false;
  networking.firewall.allowedTCPPorts = [25];
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [465 993]; # SMTP, IMAP (both SSL)

  # Prefer ipv4 and use main ipv6 to avoid reverse DNS issues
  # CHANGEME when switching hosts
  services.postfix.settings.main = {
    # Authentication is only available through the Tailscale-restricted submissions service.
    smtpd_sasl_auth_enable = lib.mkForce false;
    smtp_bind_address6 = "2001:19f0:b800:1bf8::1";
    smtp_address_preference = "ipv4";
  };

  sops.secrets = {
    gabriel-mail-password.sopsFile = ../secrets.yaml;
    grafana-mail-password-hashed.sopsFile = ../secrets.yaml;
    media-mail-password-hashed.sopsFile = ../secrets.yaml;
    firefly-mail-password-hashed.sopsFile = ../secrets.yaml;
    calibre-mail-password-hashed.sopsFile = ../secrets.yaml;
    lumis-mail-password-hashed.sopsFile = ../secrets.yaml;
  };

  # IMAP/SMTP still need this certificate without a webmail application.
  services.nginx.virtualHosts.${config.mailserver.fqdn} = {
    enableACME = true;
    extraConfig = ''
      allow 127.0.0.1;
      allow ::1;
      allow ${config.services.headscale.settings.prefixes.v4};
      allow ${config.services.headscale.settings.prefixes.v6};
      deny all;
    '';
    locations."/".return = "404";
  };

  # Autoconfig
  services.automx2 = {
    enable = true;
    domain = "m7.rs";
    settings = {
      provider = "Gabriel Fontes";
      domains = ["m7.rs" "misterio.me" "gsfontes.com"];
      servers = [
        {
          type = "imap";
          name = "mail.m7.rs";
        }
        {
          type = "smtp";
          name = "mail.m7.rs";
        }
      ];
    };
  };
  services.nginx.virtualHosts."autoconfig.m7.rs".serverAliases = [
    "autoconfig.gsfontes.com"
    "autoconfig.misterio.me"
    "autodiscover.gsfontes.com"
    "autodiscover.misterio.me"
  ];

  environment.persistence = {
    "/persist".directories = [
      {
        directory = "/var/lib/rspamd";
        user = "rspamd";
        group = "rspamd";
        mode = "0700";
      }
    ];
  };

  systemd.tmpfiles.settings.srv-mail."/srv/mail".d = {
    mode = "755"; # The inner dirs have more strict permissions, set by their homeMode
  };
}

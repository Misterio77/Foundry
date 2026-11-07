{lib}: let
  upsert = object: matchOn: value: {
    "@type" = "upsert";
    inherit object matchOn value;
  };
  update = object: value: {
    "@type" = "update";
    inherit object value;
  };
  set = values: lib.genAttrs values (_: true);
in [
  (upsert "Domain" ["name"] {
    lumis = {
      name = "lumis.cards";
      enable = true;
      catchAllAddress = "hi@m7.rs";
      certificateManagement."@type" = "Manual";
      dkimManagement."@type" = "Manual";
      dnsManagement."@type" = "Manual";
    };
  })
  (upsert "Directory" ["description"] {
    gablogin = {
      "@type" = "Oidc";
      description = "Gablogin Lumis";
      issuerUrl = "https://auth.m7.rs/application/o/stalwart/";
      claimUsername = "mail_account";
      acceptedAudiences = set ["stalwart"];
      unscopedTokens = "reject";
      skipAudienceValidation = false;
      # Authentik copies nonce into access JWTs; ID tokens still lack required scopes.
      allowIdTokenClaims = true;
    };
  })
  (upsert "Role" ["description"] {
    lumis-user = {
      description = "Lumis mail and DAV user";
      enabledPermissions = set (import ./stalwart-user-permissions.nix);
    };
  })
  (update "Authentication" {
    directoryId = "#gablogin";
    defaultUserRoleIds = set ["#lumis-user"];
  })
  (upsert "Account" ["emailAddress"] {
    contato = {
      "@type" = "User";
      emailAddress = "contato@lumis.cards";
      name = "contato";
      description = "Lumis contato";
      domainId = "#lumis";
      roles."@type" = "User";
      permissions = {
        "@type" = "Merge";
        disabledPermissions = set [
          "sysAccountPasswordUpdate"
          "sysAppPasswordCreate"
          "sysAppPasswordUpdate"
          "sysApiKeyCreate"
          "sysApiKeyUpdate"
        ];
      };
    };
  })
  (upsert "Certificate" ["certificate"] {
    public-tls = {
      certificate.file = "/var/lib/acme/mail.lumis.cards/fullchain.pem";
      privateKey.file = "/var/lib/acme/mail.lumis.cards/key.pem";
    };
  })
  (update "SystemSettings" {
    defaultHostname = "mail.lumis.cards";
    defaultDomainId = "#lumis";
    defaultCertificateId = "#public-tls";
  })
  (upsert "NetworkListener" ["name"] {
    smtp = {
      name = "smtp";
      protocol = "smtp";
      bind = set ["[::]:25"];
      useTls = true;
      implicitTls = false;
    };
    submissions = {
      name = "submissions";
      protocol = "smtp";
      bind = set ["[::]:465"];
      useTls = true;
      implicitTls = true;
    };
    imaps = {
      name = "imaps";
      protocol = "imap";
      bind = set ["[::]:993"];
      useTls = true;
      implicitTls = true;
    };
    http = {
      name = "http";
      protocol = "http";
      bind = set ["127.0.0.1:8080"];
      useTls = false;
      implicitTls = false;
    };
    sieve = {
      name = "sieve";
      protocol = "manageSieve";
      bind = set ["127.0.0.1:4190"];
      useTls = true;
      implicitTls = false;
    };
  })
  (update "DnsResolver" {
    "@type" = "Cloudflare";
    useTls = false;
  })
  (upsert "MtaConnectionStrategy" ["name"] {
    public = {
      name = "public";
      localIps = {
        "0".localIp = "155.138.245.163";
        "1".localIp = "2001:19f0:6401:cf2::1";
      };
    };
  })
  (update "MtaOutboundStrategy" {
    connection = {
      match = {};
      "else" = "'public'";
    };
  })
  (update "Http" {clientIpSource = "xForwardedFor";})
  (update "Search" {
    indexEmailFields = set ["from" "to" "cc" "bcc" "subject" "body" "attachment" "headers"];
  })
  (update "SieveUserInterpreter" {maxRedirects = 2;})
  (update "MtaStageAuth" {
    saslMechanisms = {
      match."0" = {
        "if" = "local_port != 25 && is_tls";
        "then" = "[oauthbearer, xoauth2]";
      };
      "else" = "false";
    };
  })
  (upsert "DkimSignature" ["selector" "domainId"] {
    rsa = {
      "@type" = "Dkim1RsaSha256";
      domainId = "#lumis";
      selector = "202611r";
      stage = "active";
      privateKey.file = "/var/lib/stalwart/v1/keys/202611r.pem";
    };
    ed25519 = {
      "@type" = "Dkim1Ed25519Sha256";
      domainId = "#lumis";
      selector = "202611e";
      stage = "active";
      privateKey.file = "/var/lib/stalwart/v1/keys/202611e.pem";
    };
  })
]

{
  config,
  lib,
  outputs,
  pkgs,
  ...
}: let
  jf = config.services.jellyfin;
  port = 8096;
  pluginDir = "${jf.dataDir}/plugins/Foundry-OIDC";
  pluginConfig = pkgs.writeText "Jellyfin.Plugin.OIDC.xml" ''
    <?xml version="1.0" encoding="utf-8"?>
    <PluginConfiguration>
      <Providers>
        <OidcProviderConfig>
          <ProviderId>authentik</ProviderId>
          <DisplayName>Gablogin</DisplayName>
          <Authority>https://auth.m7.rs/application/o/jellyfin/</Authority>
          <ClientId>jellyfin</ClientId>
          <ClientSecretFile>${config.sops.secrets.authentik-jellyfin-client-secret.path}</ClientSecretFile>
          <Scopes>openid profile email</Scopes>
          <RoleClaim>groups</RoleClaim>
          <UsernameClaim>preferred_username</UsernameClaim>
          <SyncProfileImage>false</SyncProfileImage>
          <SyncDisplayName>false</SyncDisplayName>
          <TrustedForEmailLinking>false</TrustedForEmailLinking>
          <StrictAccessTokenValidation>true</StrictAccessTokenValidation>
          <Enabled>true</Enabled>
          <PinnedAuthority>https://auth.m7.rs/application/o/jellyfin/</PinnedAuthority>
          <PinnedIssuer>https://auth.m7.rs/application/o/jellyfin/</PinnedIssuer>
          <PinnedAuthorizeEndpoint>https://auth.m7.rs/application/o/authorize/</PinnedAuthorizeEndpoint>
          <PinnedTokenEndpoint>https://auth.m7.rs/application/o/token/</PinnedTokenEndpoint>
          <PinnedJwksUri>https://auth.m7.rs/application/o/jellyfin/jwks/</PinnedJwksUri>
          <PinnedUserInfoEndpoint>https://auth.m7.rs/application/o/userinfo/</PinnedUserInfoEndpoint>
        </OidcProviderConfig>
      </Providers>
      <AutoCreateUsers>false</AutoCreateUsers>
      <MigrateLocalUsers>false</MigrateLocalUsers>
      <LinkExistingUsersByEmail>false</LinkExistingUsersByEmail>
      <AllowedGroups><string>jellyfin-access</string></AllowedGroups>
      <DefaultRoleName />
      <!-- Keep existing per-user permissions, including library restrictions and administrator status. -->
      <ManageUserPolicy>false</ManageUserPolicy>
      <EnableLibraryAccessManagement>false</EnableLibraryAccessManagement>
      <ManageLoginButtonBranding>false</ManageLoginButtonBranding>
      <HideManualLogin>true</HideManualLogin>
      <LoginTitle />
      <ServerBaseUrl>https://media.m7.rs</ServerBaseUrl>
    </PluginConfiguration>
  '';
in {
  # https://jellyfin.org/docs/general/post-install/networking/
  # TODO: https://github.com/Sveske-Juice/declarative-jellyfin
  services = {
    jellyfin.enable = true;
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
        # ASP.NET routes are case-insensitive; cover /Metrics too.
        locations."~* ^/metrics(?:/|$)" = {
          proxyPass = "http://localhost:${toString port}";
          extraConfig = ''
            allow 127.0.0.1;
            allow ::1;
            allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v4};
            allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v6};
            deny all;
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
    sopsFile = ../../secrets.yaml;
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
        # Refuse the plugin's username-based recovery if an established identity map is lost.
        ${pkgs.python3}/bin/python3 <<'PY'
        import json
        import re
        import sqlite3
        import xml.etree.ElementTree as ET
        from pathlib import Path
        from uuid import UUID

        root = Path(${builtins.toJSON (toString jf.dataDir)})
        db = root / "data/jellyfin.db"
        mapping = root / "plugins/configurations/Jellyfin.Plugin.OIDC.UserProviderMap.json"
        with sqlite3.connect(db.as_uri() + "?mode=ro", uri=True) as connection:
            provider = "Jellyfin.Plugin.OIDC.Auth.OidcAuthProvider"
            if connection.execute(
                "SELECT 1 FROM Users WHERE AuthenticationProviderId IS NOT ? LIMIT 1", (provider,)
            ).fetchone():
                raise SystemExit("Local authentication account found; explicitly bind it before starting Jellyfin")
            users = connection.execute("SELECT Id FROM Users").fetchall()
        entries = json.loads(mapping.read_text()) if mapping.exists() else []
        if not isinstance(entries, list):
            raise SystemExit("OIDC identity map must be an array; restore it before starting Jellyfin")
        identities, owners, names = set(), set(), set()
        for entry in entries:
            if not isinstance(entry, dict) or any(
                not isinstance(entry.get(key), str) or not entry[key].strip()
                for key in ("UserId", "ProviderId", "Subject", "Username")
            ):
                raise SystemExit("Incomplete OIDC identity map; restore it before starting Jellyfin")
            identity = (entry["ProviderId"].casefold(), entry["Subject"])
            owner, name = UUID(entry["UserId"]), entry["Username"].casefold()
            if identity[0] != "authentik" or identity in identities or owner in owners or name in names:
                raise SystemExit("Conflicting OIDC identity map; restore it before starting Jellyfin")
            identities.add(identity)
            owners.add(owner)
            names.add(name)
        if any(UUID(user_id) not in owners for (user_id,) in users):
            raise SystemExit("Missing OIDC account binding; restore the identity map before starting Jellyfin")

        branding = Path(${builtins.toJSON "${jf.configDir}/branding.xml"})
        tree = ET.parse(branding) if branding.exists() else ET.ElementTree(ET.Element("BrandingOptions"))
        blocks = {
            "LoginDisclaimer": '<div class="foundry-oidc-login"><a class="raised button-submit block emby-button" href="/sso/OIDC/Start/authentik">Entrar com Gablogin</a></div>',
            "CustomCss": """#loginPage .loginDisclaimerContainer { display: block; margin-top: .5em; }
        #loginPage .loginDisclaimer { width: 100%; margin: 0; }
        #loginPage .btnQuick,
        #loginPage .foundry-oidc-login .emby-button {
            display: flex;
            align-items: center;
            justify-content: center;
            box-sizing: border-box;
            width: 100%;
            min-height: 3.25em;
            margin: .25em 0;
            padding: .9em 1em;
            font-size: inherit;
            font-weight: 600;
            line-height: 1.35;
        }
        #loginPage .manualLoginForm,
        #loginPage .visualLoginForm,
        #loginPage .btnManual,
        #loginPage .readOnlyContent .btnForgotPassword { display: none; }""",
        }
        changed = False
        for tag, block in blocks.items():
            element = tree.getroot().find(tag)
            if element is None:
                element = ET.SubElement(tree.getroot(), tag)
            start, end = ("<!-- foundry-oidc:start -->", "<!-- foundry-oidc:end -->") if tag == "LoginDisclaimer" else ("/* foundry-oidc:start */", "/* foundry-oidc:end */")
            previous = element.text or ""
            existing = re.sub(re.escape(start) + r".*?" + re.escape(end), "", previous, flags=re.S).rstrip()
            element.text = existing + ("\n" if existing else "") + start + "\n" + block + "\n" + end
            changed |= element.text != previous
        if changed:
            branding.parent.mkdir(parents=True, exist_ok=True)
            temporary = branding.with_suffix(".xml.tmp")
            tree.write(temporary, encoding="utf-8", xml_declaration=True)
            temporary.replace(branding)
        PY
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

{lib}: let
  evaluate = settings: enable:
    (lib.evalModules {
      specialArgs.pkgs.formats.json = _: {
        type = lib.types.attrs;
        generate = _: builtins.toJSON;
      };
      modules = [
        ../modules/nixos/seerr.nix
        {
          options = {
            services.seerr.enable = lib.mkOption {default = true;};
            systemd.services = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = {};
            };
            assertions = lib.mkOption {
              type = lib.types.listOf lib.types.attrs;
              default = [];
            };
          };
          config.services.seerr.declarative = {
            inherit settings enable;
            owner = {
              provider = "test";
              subject = "owner";
              email = "owner@example.com";
              username = "owner";
            };
          };
        }
      ];
    }).config;
  settings = {
    oidc.providers = [{clientSecret.file = "/run/secrets/oidc";}];
    notifications.agents.email.options.authPass.file = "/run/secrets/oidc";
    radarr = [{apiKey.file = "/elsewhere/oidc";}];
    ordinary = {
      enabled = true;
      count = 2;
      empty = null;
      list = ["literal" false];
      notAReference = {
        file = "/untouched";
        extra = "keep";
      };
    };
  };
  result = evaluate settings true;
  service = result.systemd.services.seerr;
  generated = builtins.fromJSON service.environment.SEERR_CONFIG_FILE;
  credentialName = file: "secret-${builtins.hashString "sha256" file}";
  credentialPath = file: "/run/credentials/seerr.service/${credentialName file}";
in
  lib.runTests {
    testNestedReferences = {
      expr = generated.settings;
      expected =
        settings
        // {
          oidc.providers = [{clientSecret.file = credentialPath "/run/secrets/oidc";}];
          notifications.agents.email.options.authPass.file = credentialPath "/run/secrets/oidc";
          radarr = [{apiKey.file = credentialPath "/elsewhere/oidc";}];
        };
    };
    testDeduplicationAndBasenameCollisions = {
      expr = lib.sort builtins.lessThan service.serviceConfig.LoadCredential;
      expected = lib.sort builtins.lessThan [
        "${credentialName "/run/secrets/oidc"}:/run/secrets/oidc"
        "${credentialName "/elsewhere/oidc"}:/elsewhere/oidc"
      ];
    };
    testStableNames = {
      expr = let
        extended = evaluate (settings // {another.file = "/a/new/secret";}) true;
      in
        (builtins.fromJSON extended.systemd.services.seerr.environment.SEERR_CONFIG_FILE).settings.oidc;
      expected = generated.settings.oidc;
    };
    testAbsolutePaths = {
      expr = map (a: a.assertion) result.assertions;
      expected = [true];
    };
    testRelativePathRejected = {
      expr = map (a: a.assertion) (evaluate {secret.file = "relative/secret";} true).assertions;
      expected = [false];
    };
    testNoSecrets = {
      expr = (evaluate {main.applicationTitle = "Test";} true).systemd.services.seerr.serviceConfig.LoadCredential;
      expected = [];
    };
    testDisabled = {
      expr = (evaluate settings false).systemd.services;
      expected = {};
    };
  }

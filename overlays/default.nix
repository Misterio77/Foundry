{
  outputs,
  inputs,
}: let
  addPatches = pkg: patches:
    pkg.overrideAttrs (oldAttrs: {
      patches = (oldAttrs.patches or []) ++ patches;
    });
in {
  # For every flake input, aliases 'pkgs.inputs.${flake}' to
  # 'inputs.${flake}.packages.${pkgs.stdenv.hostPlatform.system}' or
  # 'inputs.${flake}.legacyPackages.${pkgs.stdenv.hostPlatform.system}'
  flake-inputs = final: _: {
    inputs =
      builtins.mapAttrs (
        _: flake: let
          legacyPackages = (flake.legacyPackages or {}).${final.stdenv.hostPlatform.system} or {};
          packages = (flake.packages or {}).${final.stdenv.hostPlatform.system} or {};
        in
          if legacyPackages != {}
          then legacyPackages
          else packages
      )
      inputs;
  };

  # Adds my custom packages
  additions = final: prev:
    import ../pkgs {
      inherit inputs;
      pkgs = final;
    }
    // {
      formats = (prev.formats or {}) // import ../pkgs/formats {pkgs = final;};
    };

  # Modifies existing packages
  modifications = final: prev: {
    # Maildir flag removal must replace aerc's cached flags, not OR into them.
    aerc = addPatches prev.aerc [./aerc-maildir-replace-flags.patch];

    calibre-web = (addPatches prev.calibre-web [./calibre-web-proxy.patch]).overrideAttrs (old: {
      postInstallCheck =
        (old.postInstallCheck or "")
        + ''
          ${final.python3.withPackages (ps: [ps.flask ps.sqlalchemy])}/bin/python tests/test_foundry_proxy.py src/calibreweb/cps
        '';
      doInstallCheck = true;
    });

    immich = addPatches prev.immich [./immich-oidc-avatar.patch];

    radicale = addPatches prev.radicale [./radicale-login-username.patch ./radicale-share-picker.patch];

    grafana = assert final.lib.versions.majorMinor prev.grafana.version == "13.3";
      prev.grafana.overrideAttrs (old: {
        patches = (old.patches or []) ++ [./grafana-oidc-backchannel.patch ./grafana-oidc-picture.patch];
        postCheck =
          (old.postCheck or "")
          + ''
            export GOMAXPROCS=4
            go test -p 4 -tags oss -count=1 \
              ./pkg/login/oidcbackchannel \
              ./pkg/login/social/connectors \
              ./pkg/api/dtos \
              ./pkg/services/user/userimpl \
              ./pkg/services/authn/authnimpl/sync \
              ./pkg/services/navtree/navtreeimpl \
              ./pkg/services/org/orgimpl \
              ./pkg/services/team/teamimpl \
              ./pkg/services/team/teamapi \
              ./pkg/services/annotations/annotationsimpl \
              ./pkg/services/accesscontrol/resourcepermissions \
              ./pkg/services/auth/authimpl \
              ./pkg/services/authn/clients \
              ./pkg/services/authn/authnimpl \
              ./pkg/services/ssosettings/strategies \
              ./pkg/middleware/csrf \
              ./pkg/services/sqlstore/migrations
            go test -p 4 -tags oss -count=1 ./pkg/api \
              -run 'Test(OAuthLogin|OIDCBackchannelLogout)'
            ${final.python3.withPackages (ps: [ps.cryptography])}/bin/python3 \
              scripts/test-oidc-backchannel.py "$GOPATH/bin/grafana" "$PWD"
          '';
      });

    # https://todo.sr.ht/~scoopta/wofi/174
    wofi = addPatches prev.wofi [./wofi-run-shell.patch];

    nixbot = addPatches final.inputs.nixbot.nixbot [./nixbot-store-paths.patch];

    oama =
      (addPatches prev.oama [
        ./oama-refresh-margin.patch
        ./oama-refresh-token-rotation.patch
      ]).overrideAttrs (_: {
        nativeBuildInputs = [final.makeBinaryWrapper];
        postInstall = ''
          wrapProgram $out/bin/oama \
            --prefix PATH : ${final.lib.makeBinPath [
            final.coreutils
            final.libsecret
            final.gnupg
          ]}
        '';
      });

    firefly-iii = prev.firefly-iii.overrideAttrs (old: rec {
      pname = "firefly-iii";
      version = "6.4.22";
      src = final.fetchFromGitHub {
        owner = "firefly-iii";
        repo = "firefly-iii";
        tag = "v${version}";
        hash = "sha256-i20D0/z6GA7pZYrWvRJ8tUlptNI5Cl/e9UY0hKg9SP8=";
      };
      composerVendor = final.php.mkComposerVendor {
        inherit pname src version;
        composerStrictValidation = true;
        strictDeps = true;
        vendorHash = "sha256-m+esW/yQs/GSwnw2iqVfSMXCf6/5M4634GUbt4Nnvbg=";
      };
      npmDeps = final.fetchNpmDeps {
        inherit src;
        name = "${pname}-npm-deps";
        hash = "sha256-pu8dxL0NRB1cyqlQEf2zT2wdVp2fbe+Vp85qMs7f6s0=";
      };
      passthru =
        old.passthru
        // {
          releaseTarball = final.fetchzip {
            pname = "firefly-iii-release-tarball";
            inherit version;
            url = "https://github.com/firefly-iii/firefly-iii/releases/download/v${version}/FireflyIII-v${version}.tar.gz";
            stripRoot = false;
            hash = "sha256-5o8fw2WDIdM9IQImTWVasf7pV2XK2LJ2WuSNSkdzGdE=";
          };
        };
      preInstall = ''
        npm run prod --workspace=v1
        npm run build --workspace=v2
      '';
      # This release predates the v3 frontend and its separate translations.
      postInstall = ''
        chmod -R u+w $out/share
        mv $out/share/php/firefly-iii/* $out/
        cp -r ${passthru.releaseTarball}/resources/lang/* $out/resources/lang/

        rm -R $out/share $out/storage $out/bootstrap/cache $out/node_modules
      '';
    });

    authentikComponents =
      ((inputs.authentik-nix.lib.mkAuthentikScope {pkgs = final;}).overrideScope (_: prev: let
        patches = [
          ./authentik-avatar-cache-url.patch
          # Track RP logins beyond token expiry so aged sessions still log out clients.
          (final.fetchpatch {
            url = "https://github.com/goauthentik/authentik/pull/26310.patch";
            hash = "sha256-DLTnbpIDfVwOAq68vF+Yriig1m54mXFNRBalTjQrouk=";
          })
          # Unfinished flows must not block a subsequent app's logout.
          (final.fetchpatch {
            url = "https://github.com/goauthentik/authentik/pull/26565.patch";
            hash = "sha256-QXL7ESF5D8Yy5A3dwIl0iGYzU3RKcs7WsQq68SbTvd8=";
          })
        ];
      in {
        # Runtime imports use the working-directory source before site-packages.
        patches = prev.patches ++ patches;
        pythonOverlay = final.lib.composeExtensions prev.pythonOverlay (_: pythonPrev: {
          authentik = addPatches pythonPrev.authentik patches;
        });
      })).authentikComponents;

    # Automatic sync passes no reference, so ffsubsync picks whichever embedded
    # subtitle track ends last -- won by the Signs & Songs track, whose trailing
    # title card outlasts the final line of dialogue. Skip the non-dialogue
    # tracks outright, and select among the rest by speech rather than by final
    # timestamp so a mistagged track can't win either.
    bazarr = addPatches prev.bazarr [
      ./bazarr-subsync-skip-non-dialogue-streams.patch
      ./bazarr-ffsubsync-reference-by-speech.patch
    ];

    # Test progress pads each update to Hydra's PTY width, exhausting its log limit.
    # https://github.com/NixOS/nixpkgs/issues/570642
    duckdb = prev.duckdb.overrideAttrs (oldAttrs: {
      postPatch =
        (oldAttrs.postPatch or "")
        + ''
          substituteInPlace third_party/catch/catch.hpp \
            --replace-fail 'renderTestProgress(current_test, total_tests_run, testCase->name);' ';'
        '';
    });

    runelite = addPatches prev.runelite [./runelite-developer-mode.patch];

    qutebrowser = prev.qutebrowser.overrideAttrs (oldAttrs: {
      preFixup =
        oldAttrs.preFixup
        +
        # Fix for https://github.com/NixOS/nixpkgs/issues/168484
        (let
          schemaPath = package: "${package}/share/gsettings-schemas/${package.name}";
        in ''
          makeWrapperArgs+=(
            --prefix GIO_EXTRA_MODULES : "${final.lib.getLib final.dconf}/lib/gio/modules"
            --prefix XDG_DATA_DIRS : ${schemaPath final.gsettings-desktop-schemas}
            --prefix XDG_DATA_DIRS : ${schemaPath final.gtk3}
          )
        '');
      patches =
        (oldAttrs.patches or [])
        ++ [
          # Repaint tabs when colorscheme changes
          ./qutebrowser-refresh-tab-colorscheme.patch
        ];
    });

    helix-unwrapped = addPatches prev.helix-unwrapped [
      (final.fetchpatch {
        url = "https://github.com/helix-editor/helix/commit/52bf5e94898bb10de22a4142f08470993151e5c8.diff";
        hash = "sha256-A84GYJzchfi9ncfmH0FVWwef8hYOKEQ7alLqHr7vPtY=";
      })
    ];

    # Avoid refreshing the entire movie library when the real-time monitor sees
    # a new sidecar file in an existing movie directory.
    # https://github.com/jellyfin/jellyfin/pull/16228
    jellyfin = addPatches prev.jellyfin [
      (final.fetchpatch {
        url = "https://github.com/jellyfin/jellyfin/commit/6dd862fc8465c7352a77bab0bf8f4386d4059f9b.diff";
        hash = "sha256-8quKcz7VhqQGkd8ZTSqzhBKdAE/4Lc2avFFI/rIuUNc=";
      })
      (final.fetchpatch {
        url = "https://github.com/jellyfin/jellyfin/commit/9605e182dbf0272d23891087111d38dfeee9a654.diff";
        hash = "sha256-s9JBIWHwgLyralGKHUMWV5iTmdR1IIopCW7eI5HSY9Q=";
      })
    ];

    # https://gitlab.freedesktop.org/mstoeckl/waypipe/-/releases#v0.11.3
    # Raise when it's time to remove
    waypipe = assert final.lib.versionOlder prev.waypipe.version "0.11.3";
      prev.waypipe.overrideAttrs (finalAttrs: _: {
        version = "0.11.3";
        src = final.fetchFromGitLab {
          domain = "gitlab.freedesktop.org";
          owner = "mstoeckl";
          repo = "waypipe";
          tag = "v${finalAttrs.version}";
          hash = "sha256-PAFqg+4gw9AC9u0QAnxtgC5mNpMTADBpO/PtRgEXa2E=";
        };
        cargoDeps = final.rustPlatform.fetchCargoVendor {
          inherit (finalAttrs) pname version src;
          hash = "sha256-1ByTuQ2PenNPgWFHbAUjhGj2WCwlZ9sd5esloSzqfBI=";
        };
      });

    wl-clipboard = addPatches prev.wl-clipboard [./wl-clipboard-secrets.diff];

    pass = addPatches prev.pass [./pass-wlclipboard-secret.diff];

    # Fork of upstream carrying local commits (pending upstream).
    hax = final.callPackage ../pkgs/hax {};

    # https://github.com/pimutils/vdirsyncer/pull/1221
    vdirsyncer = addPatches prev.vdirsyncer [
      (final.fetchpatch {
        url = "https://github.com/pimutils/vdirsyncer/pull/1221.patch";
        hash = "sha256-ECauSuayYBKslVdb0K4nGfK0Aqt9bgqnjKpdnV7nJfc=";
      })
      # token_command doesn't provide a client ID to use as the user agent.
      ./vdirsyncer-token-command-useragent.patch
      ./vdirsyncer-dav-token-command.patch
    ];

    todoman = addPatches prev.todoman [
      # https://github.com/pimutils/todoman/pull/594
      ./todoman-subtasks.patch
      ./todoman-disable-uid-hostname-suffix.diff
    ];

    # https://github.com/ValveSoftware/gamescope/issues/1622
    gamescope = prev.gamescope.overrideAttrs (_: {
      NIX_CFLAGS_COMPILE = ["-fno-fast-math"];
    });

    # Force $XDG_CONFIG_DIR/hdos.
    hdos = prev.hdos.overrideAttrs (_: let
      inherit (final) lib openjdk11 libGL;
    in {
      installPhase = ''
        runHook preInstall
        makeWrapper ${lib.getExe openjdk11} $out/bin/hdos \
          --run "export XDG_CONFIG_DIR=\"\''${XDG_CONFIG_DIR:-\$HOME/.config}\"" \
          --run "export HDOS_DIR=\"\$XDG_CONFIG_DIR/hdos\"" \
          --run "export HOME=\"\$XDG_CONFIG_DIR\"" \
          --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [libGL]}" \
          --add-flags "-Dapp.user.home=\"\$HDOS_DIR\"" \
          --add-flags "-Duser.home=\"\$HDOS_DIR\"" \
          --add-flags "-jar $src"
        runHook postInstall
      '';
    });

    automatic-timezoned = prev.automatic-timezoned.overrideAttrs (old: {
      patches = [./automatic-timezoned-async-error-handling.patch];
      cargoDeps = old.cargoDeps.overrideAttrs (old: {
        vendorStaging = old.vendorStaging.overrideAttrs {
          patches = [./automatic-timezoned-async-error-handling.patch];
          outputHash = "sha256-KWDME7KRvlmW5XbwVMXc90BXBC48CCyzPh5gy1tKNXM=";
        };
      });
    });

    pi-coding-agent = prev.pi-coding-agent.overrideAttrs (finalAttrs: oldAttrs: {
      version = "1.3.0";
      src = final.fetchFromGitHub {
        owner = "earendil-works";
        repo = "pi";
        tag = "v${finalAttrs.version}";
        hash = "sha256-AsutbwnjiwwLkB5tqLW+1GdGZyLmXsU0W+SNdNhJu7U=";
      };
      npmDeps = final.fetchNpmDeps {
        name = "${finalAttrs.pname}-${finalAttrs.version}-npm-deps";
        inherit (finalAttrs) src;
        hash = "sha256-+gFyvrhkCsF99oNvs0gBmLXnDW0hWnZI/wFId7UbI6Q=";
      };
      modelData = final.fetchurl {
        url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${finalAttrs.version}.tgz";
        hash = "sha256-U0PhY5vzQ73DNE3zrWwxwFpQtoutB6xrzhCJDUtrimE=";
      };
      patches = (oldAttrs.patches or []) ++ [./pi-retry-model-access.patch];
      # Upstream removed these runtime dependencies in 1.2.0.
      postInstall =
        final.lib.replaceStrings [
          "@earendil-works/chord:packages/chord"
          "@earendil-works/pi-client:packages/client"
          "@earendil-works/pi-protocol:packages/protocol"
        ] ["" "" ""]
        oldAttrs.postInstall;
    });

    buildPiPackage = let
      inherit (final) lib buildNpmPackage fetchNpmDeps jq curl openssl cacert stdenvNoCC;
      commonDefaults = {
        pname = "pi-extension";
        version = "unstable";
        installPhase = ''
          mkdir -p $out
          cp -r . $out/
        '';
      };
      # Some pi deps ship without a lockfile integrity field
      # (https://github.com/earendil-works/pi/issues/5653). A single shared
      # placeholder integrity makes every such dep collide on one npm cache
      # entry, so a fetch race decides the winner and the FOD is
      # non-deterministic. Instead fetch each dep's real registry integrity. This
      # runs only inside the FOD, where network is available, and is
      # deterministic because prefetch-npm-deps verifies every tarball against it.
      fetchRealIntegrity = ''
        for url in $(${lib.getExe jq} -r '[.. | objects | select(has("resolved") and (has("integrity") | not)) | .resolved] | unique | .[]' package-lock.json); do
          tarball="$(mktemp)"
          # Download to a file (not a pipe) so a failed fetch aborts the build
          # instead of silently yielding an empty digest; time out and retry so a
          # stalled connection can't hang the build forever.
          ${lib.getExe curl} -sSL --fail --connect-timeout 15 --max-time 300 \
            --retry 5 --retry-all-errors --retry-delay 2 \
            --cacert "${cacert}/etc/ssl/certs/ca-bundle.crt" -o "$tarball" "$url"
          integrity="sha512-$(${lib.getExe openssl} dgst -sha512 -binary "$tarball" | base64 -w0)"
          rm -f "$tarball"
          ${lib.getExe jq} --arg url "$url" --arg integrity "$integrity" \
            '(.. | objects | select(.resolved? == $url and (has("integrity") | not))) |= (. + {integrity: $integrity})' \
            package-lock.json > fixed-package-lock.json
          mv fixed-package-lock.json package-lock.json
        done
      '';
      npmDefaults =
        commonDefaults
        // {
          npmInstallFlags = ["--omit=dev"];
          npmDepsFetcherVersion = 2;
          dontNpmBuild = true;
        };
    in
      args:
        if args.dontNpmInstall or false
        then stdenvNoCC.mkDerivation (commonDefaults // args)
        else if args ? npmDeps
        then buildNpmPackage (npmDefaults // args)
        else let
          npmDeps = fetchNpmDeps {
            inherit (args) src;
            name = "${args.pname or commonDefaults.pname}-${args.version or commonDefaults.version}-npm-deps";
            hash = args.npmDepsHash;
            fetcherVersion = 2;
            nativeBuildInputs = [jq curl openssl];
            # Run any package-specific prePatch (e.g. vendoring a lockfile)
            # before backfilling integrity for deps that still lack it.
            prePatch = (args.prePatch or "") + "\n" + fetchRealIntegrity;
          };
        in
          buildNpmPackage (npmDefaults
            // (builtins.removeAttrs args ["npmDepsHash"])
            // {
              inherit npmDeps;
              # The main build has no network, so reuse the integrity-patched
              # lockfile the FOD already produced; npmConfigHook requires it to
              # match ${npmDeps}/package-lock.json exactly, and to stay writable
              # for its own --fixup-lockfile pass.
              postPatch =
                ''
                  rm -f package-lock.json
                  cp ${npmDeps}/package-lock.json package-lock.json
                  chmod u+w package-lock.json
                ''
                + (args.postPatch or "");
            });
  };
}

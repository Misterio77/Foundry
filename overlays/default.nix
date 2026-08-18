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
  # 'inputs.${flake}.packages.${pkgs.system}' or
  # 'inputs.${flake}.legacyPackages.${pkgs.system}'
  flake-inputs = final: _: {
    inputs =
      builtins.mapAttrs (
        _: flake: let
          legacyPackages = (flake.legacyPackages or {}).${final.system} or {};
          packages = (flake.packages or {}).${final.system} or {};
        in
          if legacyPackages != {}
          then legacyPackages
          else packages
      )
      inputs;
  };

  # Adds my custom packages
  additions = final: prev:
    import ../pkgs {pkgs = final;}
    // {
      formats = (prev.formats or {}) // import ../pkgs/formats {pkgs = final;};
      roundcubePlugins = (prev.roundcubePlugins or {}) // import ../pkgs/roundcube-plugins {pkgs = final;};
    };

  # Modifies existing packages
  modifications = final: prev: {
    aerc = addPatches prev.aerc [./aerc-config-includes.patch];

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

    # Make the llama.cpp router's HF-cache scan opt-in (LLAMA_ROUTER_SCAN_CACHE)
    # so --models-preset is the single source of truth and models can be named
    # freely without untuned repo:tag twins. Patch the base so the -vulkan and
    # -rocm variants (llama-cpp.override) inherit it.
    llama-cpp = addPatches prev.llama-cpp [./llama-cpp-optional-cache-scan.patch];

    # https://gitlab.freedesktop.org/mstoeckl/waypipe/-/releases#v0.11.1
    # Raise when it's time to remove
    waypipe = assert final.lib.versionOlder prev.waypipe.version "0.11.1";
      prev.waypipe.overrideAttrs (finalAttrs: _: {
        version = "0.11.1";
        src = final.fetchFromGitLab {
          domain = "gitlab.freedesktop.org";
          owner = "mstoeckl";
          repo = "waypipe";
          tag = "v${finalAttrs.version}";
          hash = "sha256-CQgDQJudxtUc7unORE/yAa+poopiceS/a4AMOfcsKP8=";
        };
        cargoDeps = final.rustPlatform.fetchCargoVendor {
          inherit (finalAttrs) pname version src;
          hash = "sha256-qYid2YZweunwD3ETV19mAo2CrdYItD6BSZwFNolBLv4=";
        };
      });

    wl-clipboard = addPatches prev.wl-clipboard [./wl-clipboard-secrets.diff];

    pass = addPatches prev.pass [./pass-wlclipboard-secret.diff];

    vdirsyncer = addPatches prev.vdirsyncer [./vdirsyncer-fixed-oauth-token.patch];

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
      version = "0.83.0";
      src = final.fetchzip {
        url = "https://github.com/earendil-works/pi/releases/download/v${finalAttrs.version}/pi-${finalAttrs.version}-source.tar.gz";
        hash = "sha256-6gN1KVzpEGI8wx5oYmoNwtU4sfw4ZCAWanXmmnlLQ2E=";
      };
      npmDeps = final.fetchNpmDeps {
        name = "${finalAttrs.pname}-${finalAttrs.version}-npm-deps";
        inherit (finalAttrs) src;
        hash = "sha256-AbSfP1Ion8bN309NUBQb1QSn2cIIUjNONmZgls9vnYE=";
      };
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

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

    # Make the llama.cpp router's HF-cache scan opt-in (LLAMA_ROUTER_SCAN_CACHE)
    # so --models-preset is the single source of truth and models can be named
    # freely without untuned repo:tag twins. Patch the base so the -vulkan and
    # -rocm variants (llama-cpp.override) inherit it.
    llama-cpp = addPatches prev.llama-cpp [./llama-cpp-optional-cache-scan.patch];

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

    # Force $XDG_CONFIG_DIR/hdos
    # Read credentials.properties
    hdos = prev.hdos.overrideAttrs (_: let
      inherit (final) lib openjdk11 libGL;
    in {
      installPhase = ''
        runHook preInstall
        makeWrapper ${lib.getExe openjdk11} $out/bin/hdos \
          --run "export XDG_CONFIG_DIR=\"\''${XDG_CONFIG_DIR:-\$HOME/.config}\"" \
          --run "export HDOS_DIR=\"\$XDG_CONFIG_DIR/hdos\"" \
          --run "export HOME=\"\$XDG_CONFIG_DIR\"" \
          --run "set -a" \
          --run "source \"\$HDOS_DIR/credentials.properties\" || true" \
          --run "set +a" \
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

    pi-coding-agent = prev.pi-coding-agent.overrideAttrs (finalAttrs: _: {
      version = "0.80.6";
      src = final.fetchFromGitHub {
        owner = "earendil-works";
        repo = "pi";
        tag = "v${finalAttrs.version}";
        hash = "sha256-e/wcHruEcBAHDF5tKvwew7LXjVp0eraHh2k+QaL2sCA=";
      };
      npmDeps = final.fetchNpmDeps {
        name = "${finalAttrs.pname}-${finalAttrs.version}-npm-deps";
        inherit (finalAttrs) src;
        hash = "sha256-xXEOR0epZcfbXayYGyJdBiFVliamBexqA+1Sd7wlGhU=";
      };
    });

    buildPiPackage = let
      inherit (final) lib buildNpmPackage jq stdenvNoCC;
      fakeSha512 = lib.convertHash {
        hash = lib.fakeSha512;
        toHashFormat = "sri";
        hashAlgo = "sha512";
      };
      commonDefaults = {
        pname = "pi-extension";
        version = "unstable";
        installPhase = ''
          mkdir -p $out
          cp -r . $out/
        '';
      };
      npmDefaults =
        commonDefaults
        // {
          # Pi dev deps lack integrity, put fake hash to make them work
          # https://github.com/earendil-works/pi/issues/5653
          prePatch = ''
            ${lib.getExe jq} 'walk(if type == "object" and has("resolved") and (has("integrity") | not) then . + {"integrity": "${fakeSha512}"} else . end)' package-lock.json >> fixed-package-lock.json
            mv fixed-package-lock.json package-lock.json
          '';
          npmInstallFlags = ["--omit=dev"];
          npmDepsFetcherVersion = 2;
          dontNpmBuild = true;
        };
    in
      args:
        if args.dontNpmInstall or false
        then stdenvNoCC.mkDerivation (commonDefaults // args)
        else buildNpmPackage (npmDefaults // args);
  };
}

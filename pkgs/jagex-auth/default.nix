# Note: vibecoded (pi running gpt 5.5)
{
  copyDesktopItems,
  lib,
  makeDesktopItem,
  makeWrapper,
  python3,
  runCommand,
  stdenvNoCC,
  symlinkJoin,
  writeTextFile,
}: let
  desktopItem = makeDesktopItem {
    name = "jagex-auth-handler";
    desktopName = "Jagex Auth URL Handler";
    exec = "jagex-auth handle-url %u";
    mimeTypes = ["x-scheme-handler/rshub"];
    noDisplay = true;
  };
in
  stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "jagex-auth";
    version = "0-unstable";

    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./jagex_auth
        ./README.md
        ./tests
      ];
    };

    doCheck = true;
    checkPhase = ''
      runHook preCheck
      PYTHONDONTWRITEBYTECODE=1 ${lib.getExe python3} -m unittest discover -s tests -v
      runHook postCheck
    '';

    nativeBuildInputs = [
      copyDesktopItems
      makeWrapper
    ];
    desktopItems = [desktopItem];

    installPhase = ''
      runHook preInstall

      install -Dm644 jagex_auth/__init__.py $out/share/jagex-auth/jagex_auth/__init__.py
      install -Dm644 jagex_auth/__main__.py $out/share/jagex-auth/jagex_auth/__main__.py
      makeWrapper ${lib.getExe python3} $out/bin/jagex-auth \
        --set PYTHONPATH $out/share/jagex-auth \
        --add-flags "-m jagex_auth"

      runHook postInstall
    '';

    passthru.wrapLaunch = package: let
      executable = package.meta.mainProgram or package.pname;
    in
      symlinkJoin {
        inherit (package) pname version;
        paths = [package];
        nativeBuildInputs = [makeWrapper];
        postBuild = ''
          rm "$out/bin/${executable}"
          makeWrapper ${lib.getExe finalAttrs.finalPackage} "$out/bin/${executable}" \
            --add-flags ${lib.escapeShellArg "launch -- ${package}/bin/${executable}"}
        '';
        inherit (package) meta;
        passthru = (package.passthru or {}) // {unwrapped = package;};
      };

    passthru.tests.launch = import ./tests/wrapper.nix {
      inherit lib makeDesktopItem python3 runCommand symlinkJoin writeTextFile;
      jagex-auth = finalAttrs.finalPackage;
    };

    meta = {
      description = "Authenticate RuneScape clients with a Jagex account";
      mainProgram = "jagex-auth";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  })

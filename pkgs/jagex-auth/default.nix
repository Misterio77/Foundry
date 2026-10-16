# Note: vibecoded (pi running gpt 5.5)
{
  copyDesktopItems,
  lib,
  makeDesktopItem,
  makeWrapper,
  python3,
  stdenvNoCC,
  symlinkJoin,
}: let
  desktopItem = makeDesktopItem {
    name = "jagex-auth-handler";
    desktopName = "Jagex Auth URL Handler";
    exec = "jagex-auth handle-url %u";
    mimeTypes = ["x-scheme-handler/rshub"];
    noDisplay = true;
  };
in
  stdenvNoCC.mkDerivation {
    pname = "jagex-auth";
    version = "0-unstable";

    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./jagex-auth.py
        ./jagex_auth.py
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

      install -Dm644 jagex-auth.py $out/share/jagex-auth/jagex-auth.py
      install -Dm644 jagex_auth.py $out/share/jagex-auth/jagex_auth.py
      makeWrapper ${lib.getExe python3} $out/bin/jagex-auth \
        --add-flags $out/share/jagex-auth/jagex-auth.py

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
          wrapProgram "$out/bin/${executable}" \
            --run "set -a" \
            --run "source \"\''${XDG_DATA_HOME:-\$HOME/.local/share}/jagex-auth/credentials.properties\" || true" \
            --run "set +a"
        '';
        inherit (package) meta;
        passthru = (package.passthru or {}) // {unwrapped = package;};
      };

    meta = {
      description = "Authenticate RuneScape clients with a Jagex account";
      mainProgram = "jagex-auth";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  }

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
  python = python3.withPackages (ps: [ps.requests]);
  desktopItem = makeDesktopItem {
    name = "jagex-auth-handler";
    desktopName = "Jagex Auth URL Handler";
    exec = "jagex-auth handle-url %u";
    mimeTypes = ["x-scheme-handler/jagex"];
    noDisplay = true;
  };
in
  stdenvNoCC.mkDerivation {
    pname = "jagex-auth";
    version = "0-unstable";

    src = ./jagex-auth.py;
    dontUnpack = true;

    nativeBuildInputs = [
      copyDesktopItems
      makeWrapper
    ];
    desktopItems = [desktopItem];

    installPhase = ''
      runHook preInstall

      install -Dm644 $src $out/share/jagex-auth/jagex-auth.py
      makeWrapper ${lib.getExe python} $out/bin/jagex-auth \
        --add-flags $out/share/jagex-auth/jagex-auth.py \

      runHook postInstall
    '';

    passthru.wrapLaunch = package: let
      executable = package.meta.mainProgram or package.pname;
    in
      symlinkJoin {
        name = "${package.name}-jagex-auth-wrapped";
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
      description = "Small CLI for Jagex launcher OAuth tokens";
      mainProgram = "jagex-auth";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  }

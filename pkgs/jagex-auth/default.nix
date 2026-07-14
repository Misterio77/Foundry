# Note: vibecoded (pi running gpt 5.5)
{
  lib,
  makeWrapper,
  python3,
  stdenvNoCC,
  symlinkJoin,
}: let
  python = python3.withPackages (ps: [ps.requests]);
in
  stdenvNoCC.mkDerivation {
    pname = "jagex-auth";
    version = "0-unstable";

    src = ./jagex-auth.py;
    dontUnpack = true;

    nativeBuildInputs = [makeWrapper];

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

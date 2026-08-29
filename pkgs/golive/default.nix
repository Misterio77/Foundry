{
  copyDesktopItems,
  electron,
  fetchFromGitHub,
  fetchNpmDeps,
  lib,
  makeDesktopItem,
  makeWrapper,
  nodejs_22,
  npmHooks,
  stdenvNoCC,
}: let
  desktopItem = makeDesktopItem {
    name = "golive";
    desktopName = "GoLive";
    comment = "Share your screen with people in the same room";
    exec = "golive %U";
    icon = "golive";
    categories = ["Network"];
    mimeTypes = ["x-scheme-handler/golive"];
    startupWMClass = "GoLive";
  };
in
  stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "golive";
    version = "0.1.15";

    src = fetchFromGitHub {
      owner = "Nem-Tudo";
      repo = "group-sharescreen";
      rev = "v${finalAttrs.version}";
      hash = "sha256-HddLmJ+Zr5BHw5OUoPEbysOnAHPXjb8PacX4XuJBROs=";
    };

    npmDeps = fetchNpmDeps {
      inherit (finalAttrs) src;
      hash = "sha256-PLzCYQoxpeBjABESW4M+XsfRYjH02Mw1EqAufl+fbj8=";
    };

    env = {
      ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
      npm_config_ignore_scripts = "true";
    };

    nativeBuildInputs = [
      copyDesktopItems
      makeWrapper
      nodejs_22
      npmHooks.npmConfigHook
    ];

    desktopItems = [desktopItem];

    buildPhase = ''
      runHook preBuild

      npm run electron:typecheck
      npm run electron:build

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p \
        $out/lib/golive/electron/{build,dist} \
        $out/share/icons/hicolor/512x512/apps
      install -Dm444 package.json $out/lib/golive/package.json
      install -Dm444 electron/dist/*.js $out/lib/golive/electron/dist/
      install -Dm444 electron/picker.html $out/lib/golive/electron/picker.html
      install -Dm444 electron/build/icon.png $out/lib/golive/electron/build/icon.png
      install -Dm444 electron/build/icon.png \
        $out/share/icons/hicolor/512x512/apps/golive.png

      makeWrapper ${lib.getExe electron} $out/bin/golive \
        --add-flags "--class=GoLive" \
        --add-flags "$out/lib/golive"

      runHook postInstall
    '';

    meta = {
      description = "Screen sharing app for GoLive rooms";
      homepage = "https://golive.nemtudo.me";
      license = lib.licenses.unfree;
      mainProgram = "golive";
      platforms = ["x86_64-linux"];
    };
  })

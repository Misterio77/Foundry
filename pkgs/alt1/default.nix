{
  alsa-lib,
  at-spi2-atk,
  atk,
  cairo,
  copyDesktopItems,
  cups,
  dbus,
  dbus-glib,
  electron,
  expat,
  fetchFromGitHub,
  fetchNpmDeps,
  gcc,
  glib,
  gnumake,
  gtk2,
  gtk3,
  lib,
  libappindicator-gtk2,
  libappindicator-gtk3,
  libdrm,
  libgbm,
  libglvnd,
  libjpeg,
  libpng,
  libtiff,
  libudev0-shim,
  libva,
  libxcb,
  libxcb-wm,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  libx11,
  makeDesktopItem,
  makeWrapper,
  mesa,
  nodejs,
  npmHooks,
  nspr,
  nss,
  pango,
  pipewire,
  pkg-config,
  python3,
  stdenv,
  vips,
}: let
  version = "0.0.1-unstable-2026-06-25";

  desktopItem = makeDesktopItem {
    name = "alt1lite";
    desktopName = "Alt1 Toolkit";
    comment = "RuneScape toolkit and app host";
    exec = "alt1 %U";
    icon = "alt1";
    categories = ["Game" "Utility"];
    mimeTypes = ["x-scheme-handler/alt1"];
    startupWMClass = "Alt1Lite";
  };
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "alt1";
    inherit version;

    src = fetchFromGitHub {
      owner = "Arroquw";
      repo = "alt1-electron";
      rev = "a1e315490e4d7a64fd624ea3969deba36d81c39b";
      hash = "sha256-h2r/N+R1z/f2V2KilXpafxNQJxiI4j1WsAaWKCLTTmU=";
    };

    patches = [./package.patch];

    npmDeps = fetchNpmDeps {
      inherit (finalAttrs) src;
      hash = "sha256-Q1F30c6942/ZT9BocdYNmV1hXL+KRvtHSer2CS2nBI4=";
    };
    makeCacheWritable = true;
    npmInstallFlags = ["--include=dev"];

    env = {
      ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
      npm_config_nodedir = electron.headers;
      npm_config_ignore_scripts = "true";
      SHARP_IGNORE_GLOBAL_LIBVIPS = "1";
      SHARP_LIBVIPS_VERSION = vips.version;
      NIX_CFLAGS_COMPILE = toString [
        "-I${glib.dev}/include/glib-2.0"
        "-I${glib.out}/lib/glib-2.0/include"
        "-I${vips.dev}/include"
        "-lvips"
      ];
      LD_LIBRARY_PATH = lib.makeLibraryPath [
        vips
        glib
        libpng
        libjpeg
        libtiff
      ];
      NODE_ENV = "production";
      doDist = false;
    };

    nativeBuildInputs = [
      copyDesktopItems
      gcc
      gnumake
      makeWrapper
      nodejs
      npmHooks.npmConfigHook
      npmHooks.npmBuildHook
      npmHooks.npmInstallHook
      pkg-config
      python3
    ];

    buildInputs = [
      alsa-lib
      at-spi2-atk
      atk
      cairo
      cups
      dbus
      dbus-glib
      electron
      expat
      glib
      gtk2
      gtk3
      libappindicator-gtk2
      libappindicator-gtk3
      libdrm
      libgbm
      libglvnd
      libudev0-shim
      libva
      libxcb
      libxcb-wm
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxkbcommon
      libxrandr
      libx11
      mesa
      nspr
      nss
      pango
      pipewire
      vips
    ];

    desktopItems = [desktopItem];

    buildPhase = ''
      runHook preBuild

      export npm_config_cache="$TMPDIR/npm-cache"
      export npm_config_ignore_scripts=true
      export npm_config_runtime=electron
      export npm_config_target=${electron.version}
      export npm_config_disturl=https://electronjs.org/headers
      export npm_config_build_from_source=true

      npx --offline electron-rebuild \
        -f \
        -w alt1lite \
        -c.electronDist=${electron}/libexec/electron \
        -c.electronVersion=${electron.version}

      npm --offline run build -- --mode production

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p \
        $out/lib/alt1/build/Release \
        $out/lib/alt1/dist/tooltip \
        $out/share/icons/hicolor/256x256/apps
      cp -r dist $out/lib/alt1/
      cp build/Release/addon.node $out/lib/alt1/build/Release/
      cp config.json $out/lib/alt1/dist/tooltip/
      ln -s tooltip/config.json $out/lib/alt1/dist/config.json
      install -Dm644 src/imgs/alt1icon_large.png \
        $out/share/icons/hicolor/256x256/apps/alt1.png

      makeWrapper ${lib.getExe electron} $out/bin/alt1 \
        --add-flags "--ozone-platform=x11" \
        --add-flags "$out/lib/alt1/dist/alt1lite.bundle.js"

      runHook postInstall
    '';

    meta = {
      description = "Cross-platform client for Alt1 Toolkit apps";
      homepage = "https://github.com/Arroquw/alt1-electron";
      license = lib.licenses.gpl3Only;
      mainProgram = "alt1";
      platforms = ["x86_64-linux"];
    };
  })

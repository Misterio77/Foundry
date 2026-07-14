{
  lib,
  stdenvNoCC,
  fetchurl,
  buildFHSEnv,
  copyDesktopItems,
  dpkg,
  makeDesktopItem,
  makeWrapper,
  cairo,
  gdk-pixbuf,
  glib,
  gtk2,
  libcap,
  libglvnd,
  libnotify,
  libsecret,
  libsm,
  libx11,
  libxext,
  libxi,
  libxxf86vm,
  openssl_1_1,
  pango,
  SDL2,
  sdl3,
  zlib,
}: let
  version = "2.2.12";

  client = stdenvNoCC.mkDerivation {
    pname = "runescape-unwrapped";
    inherit version;

    src = fetchurl {
      url = "https://content.runescape.com/downloads/ubuntu/pool/non-free/r/runescape-launcher/runescape-launcher_${version}_amd64.deb";
      hash = "sha256-SaWUwcdxE9/xS2lvnBMI7RwafpFm3TknXoWX7AUp+gQ=";
    };

    nativeBuildInputs = [
      copyDesktopItems
      dpkg
      makeWrapper
    ];

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb --extract $src .
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      install -Dm755 usr/share/games/runescape-launcher/runescape \
        $out/libexec/runescape
      mkdir -p $out/share
      cp -r usr/share/icons $out/share/icons

      makeWrapper $out/libexec/runescape $out/bin/runescape \
        --add-flags "--configURI https://www.runescape.com/k=5/l=0/jav_config.ws" \
        --set SDL_VIDEODRIVER x11 \
        --set SDL_VIDEO_X11_WMCLASS RuneScape \
        --set PULSE_LATENCY_MSEC 100 \
        --set PULSE_PROP_OVERRIDE "application.name='RuneScape' application.icon_name='runescape' media.role='game'" \
        --unset XMODIFIERS

      runHook postInstall
    '';

    desktopItems = [
      (makeDesktopItem {
        name = "runescape";
        desktopName = "RuneScape";
        comment = "Play RuneScape 3";
        exec = "runescape";
        icon = "runescape";
        categories = ["Game"];
      })
    ];
  };
in
  buildFHSEnv {
    pname = "runescape";
    inherit version;

    targetPkgs = _: [
      client
      cairo
      gdk-pixbuf
      glib
      gtk2
      libcap
      libglvnd
      libnotify
      libsecret
      libsm
      libx11
      libxext
      libxi
      libxxf86vm
      openssl_1_1
      pango
      SDL2
      sdl3
      zlib
    ];

    runScript = "runescape";

    extraInstallCommands = ''
      mkdir -p $out/share/applications
      ln -s ${client}/share/applications/runescape.desktop \
        $out/share/applications/runescape.desktop
      ln -s ${client}/share/icons $out/share/icons
    '';

    meta = {
      description = "Official RuneScape 3 game client";
      homepage = "https://www.runescape.com/";
      license = lib.licenses.unfree;
      mainProgram = "runescape";
      platforms = ["x86_64-linux"];
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }

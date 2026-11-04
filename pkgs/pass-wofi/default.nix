{
  lib,
  stdenv,
  makeWrapper,
  pass,
  qutebrowser,
  jq,
  wofi,
  libnotify,
  wl-clipboard,
  wtype,
  findutils,
  gnused,
  coreutils,
}:
stdenv.mkDerivation {
  name = "pass-wofi";
  version = "1.0";
  src = ./pass-wofi.sh;

  nativeBuildInputs = [makeWrapper];

  dontUnpack = true;
  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    install -Dm 0755 $src $out/bin/pass-wofi
    wrapProgram $out/bin/pass-wofi --prefix PATH ':' \
      "${
      lib.makeBinPath [
        pass
        qutebrowser
        jq
        wofi
        libnotify
        wl-clipboard
        wtype
        findutils
        gnused
        coreutils
      ]
    }"
  '';

  meta = {
    description = "A wofi graphical menu for pass";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
    mainProgram = "pass-wofi";
  };
}

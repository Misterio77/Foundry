{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation rec {
  pname = "stalwart-lab";
  version = "1.0.3";

  src = fetchurl {
    url = "https://github.com/stalwartlabs/stalwart/releases/download/v${version}/stalwart-x86_64-unknown-linux-musl.tar.gz";
    hash = "sha256-+GH3/UmPmGvGKg1tmbSZPjRJze1+5XpOxHOMEdldsBM=";
  };
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 stalwart "$out/bin/stalwart"
    runHook postInstall
  '';

  meta = {
    description = "Pinned upstream Stalwart binary for isolated migration experiments only";
    homepage = "https://github.com/stalwartlabs/stalwart";
    license = lib.licenses.agpl3Only;
    platforms = ["x86_64-linux"];
    mainProgram = "stalwart";
  };
}

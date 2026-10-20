{
  lib,
  stdenvNoCC,
  nodejs,
  makeWrapper,
}:
stdenvNoCC.mkDerivation {
  pname = "web-search";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [nodejs makeWrapper];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    node --test test.mjs
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/web-search" "$out/bin"
    cp cli.mjs search.mjs "$out/lib/web-search/"
    makeWrapper ${lib.getExe nodejs} "$out/bin/web-search" \
      --add-flags "$out/lib/web-search/cli.mjs"
    runHook postInstall
  '';

  meta = {
    description = "Search the web using a Kagi subscription session";
    mainProgram = "web-search";
    platforms = lib.platforms.all;
  };
}

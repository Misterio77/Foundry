{
  buildNpmPackage,
  importNpmLock,
  lib,
  makeWrapper,
  nodejs,
}:
buildNpmPackage {
  pname = "osrs-mcp";
  version = "0.1.0";
  src = ./.;

  npmDeps = importNpmLock {npmRoot = ./.;};
  npmConfigHook = importNpmLock.npmConfigHook;
  npmInstallFlags = ["--omit=dev"];
  dontNpmBuild = true;

  nativeBuildInputs = [makeWrapper];
  installPhase = ''
    mkdir -p $out/bin
    cp -r . $out/
    makeWrapper ${lib.getExe nodejs} $out/bin/osrs-mcp \
      --add-flags $out/server.mjs
  '';

  meta.mainProgram = "osrs-mcp";
}

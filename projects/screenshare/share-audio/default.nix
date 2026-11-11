{
  lib,
  buildNpmPackage,
  pipewire,
  fzf,
}:
buildNpmPackage {
  pname = "share-audio";
  version = (builtins.fromJSON (builtins.readFile ./package.json)).version;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./package-lock.json
      ./share-audio.js
      ./share-audio.test.js
    ];
  };

  npmDepsHash = "sha256-zwhNK8WycIZvoBs1PO8KFxo0bN4E1fr5iEDX+JDcViw=";
  forceEmptyCache = true;
  dontNpmBuild = true;
  makeWrapperArgs = ["--prefix" "PATH" ":" (lib.makeBinPath [pipewire fzf])];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    npm test
    runHook postCheck
  '';

  # npm omits node_modules when there are no dependencies; the install hook expects it.
  preInstall = "mkdir -p node_modules";

  meta = {
    description = "Share one application's PipeWire audio through a temporary virtual input";
    homepage = "https://github.com/misterio77/Foundry/tree/main/projects/screenshare";
    license = lib.licenses.mit;
    mainProgram = "share-audio";
    platforms = lib.platforms.linux;
  };
}

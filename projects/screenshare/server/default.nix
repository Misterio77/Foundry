{
  lib,
  buildNpmPackage,
}:
buildNpmPackage {
  pname = "screenshare-server";
  version = (builtins.fromJSON (builtins.readFile ./package.json)).version;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./package-lock.json
      ./server.js
      ./server.test.js
      ./app.test.js
      ./public
    ];
  };

  npmDepsHash = "sha256-qmySugYiXQv3O4bzbhluO76G6JXQpedV4r0I7fNkQZs=";
  dontNpmBuild = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    npm test
    runHook postCheck
  '';

  meta = {
    description = "Peer-to-peer screen and audio sharing server";
    homepage = "https://github.com/misterio77/Foundry/tree/main/projects/screenshare";
    license = lib.licenses.mit;
    mainProgram = "screenshare-server";
    platforms = lib.platforms.unix;
  };
}

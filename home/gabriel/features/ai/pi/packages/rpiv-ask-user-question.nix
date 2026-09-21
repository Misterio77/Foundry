{pkgs, ...}: let
  version = "2.11.0";
  rpivAskUserQuestion = pkgs.buildPiPackage {
    pname = "rpiv-ask-user-question";
    inherit version;
    src = pkgs.fetchzip {
      url = "https://registry.npmjs.org/@juicesharp/rpiv-ask-user-question/-/rpiv-ask-user-question-${version}.tgz";
      hash = "sha256-d7wkiK6X+1+n/DgJ/cYY7H8PSfdH7ghwVOu9jS0CHwE=";
    };
    prePatch = ''
      ${pkgs.lib.getExe pkgs.jq} 'del(.devDependencies)' package.json > package.json.tmp
      mv package.json.tmp package.json
      cp ${./locks/rpiv-ask-user-question.json} package-lock.json
    '';
    npmInstallFlags = ["--omit=dev" "--omit=peer" "--legacy-peer-deps"];
    npmDepsHash = "sha256-MDbIXgW95MFkh6xpPcWThO08VqHRl/PykjNTHZydO1o=";
  };
in {
  programs.pi-coding-agent.settings.packages = [rpivAskUserQuestion];
}

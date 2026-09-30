{pkgs, ...}: let
  version = "2.12.0";
  rpivAskUserQuestion = pkgs.buildPiPackage {
    pname = "rpiv-ask-user-question";
    inherit version;
    src = pkgs.fetchzip {
      url = "https://registry.npmjs.org/@juicesharp/rpiv-ask-user-question/-/rpiv-ask-user-question-${version}.tgz";
      hash = "sha256-SGnomAwAyFrgqOMIOsKMGTYrdbyAf02gC68wI3s+3b0=";
    };
    prePatch = ''
      ${pkgs.lib.getExe pkgs.jq} 'del(.devDependencies)' package.json > package.json.tmp
      mv package.json.tmp package.json
      cp ${./locks/rpiv-ask-user-question.json} package-lock.json
    '';
    npmInstallFlags = ["--omit=dev" "--omit=peer" "--legacy-peer-deps"];
    npmDepsHash = "sha256-mWt1AvLkuitxPYF5vX/uXQd07X6zD3iQr1eCXbnyV7M=";
  };
in {
  programs.pi-coding-agent.settings.packages = [rpivAskUserQuestion];
}

{pkgs, ...}: let
  version = "2.13.9";
  rpivAskUserQuestion = pkgs.buildPiPackage {
    pname = "rpiv-ask-user-question";
    inherit version;
    src = pkgs.fetchzip {
      url = "https://registry.npmjs.org/@juicesharp/rpiv-ask-user-question/-/rpiv-ask-user-question-${version}.tgz";
      hash = "sha256-inH5jksp8FaES75l6GGcDEDNXDygMx3qxoG195tZk5M=";
    };
    prePatch = ''
      ${pkgs.lib.getExe pkgs.jq} 'del(.devDependencies)' package.json > package.json.tmp
      mv package.json.tmp package.json
      cp ${./locks/rpiv-ask-user-question.json} package-lock.json
    '';
    npmInstallFlags = ["--omit=dev" "--omit=peer" "--legacy-peer-deps"];
    npmDepsHash = "sha256-Ka1PHoq0i0u7TXzBi3Q4uTzR4daLS8vRTqlc7SuTqMI=";
  };
in {
  programs.pi-coding-agent.settings.packages = [rpivAskUserQuestion];
}

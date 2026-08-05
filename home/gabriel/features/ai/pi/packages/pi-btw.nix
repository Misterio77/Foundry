{pkgs, ...}: let
  version = "0.49.3";
  piBtw = pkgs.buildPiPackage {
    pname = "pi-btw";
    inherit version;
    src = pkgs.fetchzip {
      url = "https://registry.npmjs.org/@narumitw/pi-btw/-/pi-btw-${version}.tgz";
      hash = "sha256-qKyLW/oNG8ulrw40QylqrAM18n2w051Esbo6lgWu9UY=";
    };
    prePatch = ''
      ${pkgs.lib.getExe pkgs.jq} 'del(.devDependencies)' package.json > package.json.tmp
      mv package.json.tmp package.json
      cp ${./locks/pi-btw.json} package-lock.json
    '';
    npmInstallFlags = ["--omit=dev" "--omit=peer" "--legacy-peer-deps"];
    npmDepsHash = "sha256-eRakRoz/LqnEIechpDUZlkqaiLyjWJ4/uUPpfMXRfk0=";
  };
in {
  programs.pi-coding-agent.settings.packages = [piBtw];
}

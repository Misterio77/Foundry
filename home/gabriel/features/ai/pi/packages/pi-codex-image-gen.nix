{pkgs, ...}: let
  version = "0.1.13";
  piCodexImageGen = pkgs.buildPiPackage {
    pname = "pi-codex-image-gen";
    inherit version;
    src = builtins.fetchTarball {
      url = "https://registry.npmjs.org/pi-codex-image-gen/-/pi-codex-image-gen-${version}.tgz";
      sha256 = "1r2gckq6x2apbahvhyivby18si8k2jm2sc067am5d47nqs2qs246";
    };
    prePatch = ''
      ${pkgs.lib.getExe pkgs.jq} 'del(.devDependencies, .peerDependencies)' package.json > package.json.tmp
      mv package.json.tmp package.json
      cp ${./locks/pi-codex-image-gen.json} package-lock.json
    '';
    npmDepsHash = "sha256-+CJNXQ5o8Rz3vMSRL9pozR6BjEB4Wppe1sjTnf+8lBc=";
  };
in {
  programs.pi-coding-agent.settings.packages = [piCodexImageGen];
}

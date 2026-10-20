{pkgs, ...}: let
  version = "0.2.0";
  piCodexImageGen = pkgs.buildPiPackage {
    pname = "pi-codex-image-gen";
    inherit version;
    src = builtins.fetchTarball {
      url = "https://registry.npmjs.org/pi-codex-image-gen/-/pi-codex-image-gen-${version}.tgz";
      sha256 = "0qyiiqv2sjyp93zpc4r27wqqhz79lg47d0xgmqn39wk2as1rrv4c";
    };
    prePatch = ''
      ${pkgs.lib.getExe pkgs.jq} 'del(.devDependencies, .peerDependencies)' package.json > package.json.tmp
      mv package.json.tmp package.json
      cp ${./locks/pi-codex-image-gen.json} package-lock.json
    '';
    npmDepsHash = "sha256-AjOTkAazTwliPiiw9Gp8r1shbJrqMQpx5KYhf/xWLEI=";
  };
in {
  programs.pi-coding-agent.settings.packages = [piCodexImageGen];
}

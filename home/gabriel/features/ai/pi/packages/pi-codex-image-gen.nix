{pkgs, ...}: let
  version = "0.1.12";
  piCodexImageGen = pkgs.buildPiPackage {
    pname = "pi-codex-image-gen";
    inherit version;
    src = builtins.fetchTarball {
      url = "https://registry.npmjs.org/pi-codex-image-gen/-/pi-codex-image-gen-${version}.tgz";
      sha256 = "1f1jzaf29zyd522r4dnmq3624hmx7ikmihc5s4n4k1jyxxrmslzf";
    };
    dontNpmInstall = true;
  };
in {
  programs.pi-coding-agent.settings.packages = [piCodexImageGen];
}

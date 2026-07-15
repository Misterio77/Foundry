{pkgs, ...}: let
  version = "0.1.10";
  piCodexImageGen = pkgs.buildPiPackage {
    pname = "pi-codex-image-gen";
    inherit version;
    src = builtins.fetchTarball {
      url = "https://registry.npmjs.org/pi-codex-image-gen/-/pi-codex-image-gen-${version}.tgz";
      sha256 = "1bvp3csw0scc5c5i2hc7glh5igiryjf2946zq28lsc6ls49inbyd";
    };
    patches = [./pi-codex-image-gen-references.patch];
    dontNpmInstall = true;
  };
in {
  programs.pi-coding-agent.settings.packages = [piCodexImageGen];
}

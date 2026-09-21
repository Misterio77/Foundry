{pkgs, ...}: let
  version = "0.1.13";
  piCodexImageGen = pkgs.buildPiPackage {
    pname = "pi-codex-image-gen";
    inherit version;
    src = builtins.fetchTarball {
      url = "https://registry.npmjs.org/pi-codex-image-gen/-/pi-codex-image-gen-${version}.tgz";
      sha256 = "1r2gckq6x2apbahvhyivby18si8k2jm2sc067am5d47nqs2qs246";
    };
    dontNpmInstall = true;
  };
in {
  programs.pi-coding-agent.settings.packages = [piCodexImageGen];
}

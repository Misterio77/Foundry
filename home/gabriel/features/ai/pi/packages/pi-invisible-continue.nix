{pkgs, ...}: let
  version = "0.3.7";
  piInvisibleContinue = pkgs.buildPiPackage {
    pname = "pi-invisible-continue";
    inherit version;
    src = pkgs.fetchzip {
      url = "https://registry.npmjs.org/pi-invisible-continue/-/pi-invisible-continue-${version}.tgz";
      hash = "sha256-456PA1NhOgy3SC74nEipc9sBaK5L+uUaFgfZiBTCPDk=";
    };
    dontNpmInstall = true;
  };
in {
  programs.pi-coding-agent.settings.packages = [piInvisibleContinue];
}

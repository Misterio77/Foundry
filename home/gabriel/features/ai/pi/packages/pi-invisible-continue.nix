{pkgs, ...}: let
  version = "0.3.12";
  piInvisibleContinue = pkgs.buildPiPackage {
    pname = "pi-invisible-continue";
    inherit version;
    src = pkgs.fetchzip {
      url = "https://registry.npmjs.org/pi-invisible-continue/-/pi-invisible-continue-${version}.tgz";
      hash = "sha256-PuxeZYnysgwv/PckGeSLia5RC2fwQV10tkoEfr2Uehs=";
    };
    dontNpmInstall = true;
  };
in {
  programs.pi-coding-agent.settings.packages = [piInvisibleContinue];
}

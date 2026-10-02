{pkgs, ...}: let
  version = "0.3.15";
  piInvisibleContinue = pkgs.buildPiPackage {
    pname = "pi-invisible-continue";
    inherit version;
    src = pkgs.fetchzip {
      url = "https://registry.npmjs.org/pi-invisible-continue/-/pi-invisible-continue-${version}.tgz";
      hash = "sha256-7gYTeU5ugLfKK8Hz2eFfxx31TYgY87qHb05sskEgeRM=";
    };
    dontNpmInstall = true;
  };
in {
  programs.pi-coding-agent.settings.packages = [piInvisibleContinue];
}

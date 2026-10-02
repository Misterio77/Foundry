{pkgs, ...}: let
  version = "0.6.0";
  piContextView = pkgs.buildPiPackage {
    pname = "pi-context-view";
    inherit version;
    src = pkgs.fetchzip {
      url = "https://registry.npmjs.org/pi-context-view/-/pi-context-view-${version}.tgz";
      hash = "sha256-Fliu8OX/rE3OKgb1zNQy7f7PXWRoHlTpRGUnRA0obyk=";
    };
    dontNpmInstall = true;
  };
in {
  programs.pi-coding-agent.settings.packages = [piContextView];
}

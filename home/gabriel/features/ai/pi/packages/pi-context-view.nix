{pkgs, ...}: let
  version = "0.7.2";
  piContextView = pkgs.buildPiPackage {
    pname = "pi-context-view";
    inherit version;
    src = pkgs.fetchzip {
      url = "https://registry.npmjs.org/pi-context-view/-/pi-context-view-${version}.tgz";
      hash = "sha256-IgN8Qw/x0VuWkxGJtD625FP+iWqovICI9UugALw0ZvE=";
    };
    dontNpmInstall = true;
  };
in {
  programs.pi-coding-agent.settings.packages = [piContextView];
}

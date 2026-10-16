{pkgs, ...}: let
  version = "5.3.1";
  ponytail = pkgs.buildPiPackage {
    pname = "ponytail";
    inherit version;
    src = pkgs.fetchzip {
      url = "https://registry.npmjs.org/@dietrichgebert/ponytail/-/ponytail-${version}.tgz";
      hash = "sha256-RzOFkOhZujcZHow0edkUh0hKUIArU7Z0oX0PcedD53g=";
    };
    dontNpmInstall = true;
  };
in {
  programs.pi-coding-agent.settings.packages = [ponytail];
}

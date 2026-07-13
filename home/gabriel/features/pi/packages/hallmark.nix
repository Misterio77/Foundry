{pkgs, ...}: let
  hallmark = pkgs.buildPiPackage {
    pname = "hallmark";
    version = "1.1.0";
    src = pkgs.fetchFromGitHub {
      owner = "Nutlope";
      repo = "hallmark";
      rev = "aeb42fb354ff4efa36ab475773a082315a3af2ce";
      hash = "sha256-+yPIG1XdI6hhyOH48rd20+YlFrA9Gr416tPt1OoxfwQ=";
    };
    dontNpmInstall = true;
  };
in {
  programs.pi-coding-agent.settings.packages = [hallmark];
}

{pkgs, ...}: let
  piLlamaCpp = pkgs.buildPiPackage {
    pname = "pi-llama-cpp";
    version = "0.7.2";
    src = pkgs.fetchFromGitHub {
      owner = "gsanhueza";
      repo = "pi-llama-cpp";
      tag = "0.7.2";
      hash = "sha256-7ibKGmkzKwnn3fLQvwQKIlUQ3Fil1IeOC5ixRXsStjY=";
    };
    dontNpmInstall = true;
  };
in {
  programs.pi-coding-agent.settings = {
    llamaServerUrl = "http://llm.m7.rs";
    packages = [piLlamaCpp];
  };
}

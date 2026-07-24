{pkgs, ...}: let
  letFateDecide = pkgs.buildPiPackage {
    pname = "let-fate-decide";
    version = "1.1.1";
    src = pkgs.fetchFromGitHub {
      owner = "trailofbits";
      repo = "skills";
      rev = "a56045e9ae00b3506cacefea0f672aab0a1a6e3c";
      hash = "sha256-0X3B+Ds04R2mEK3c9nZuM29qXqR3QAu0X08t6yLBx7k=";
    };
    sourceRoot = "source/plugins/let-fate-decide";
    dontNpmInstall = true;
    postPatch = ''
      substituteInPlace skills/let-fate-decide/SKILL.md \
        --replace-fail "uv run --no-config" "python3"
    '';
  };
in {
  programs.pi-coding-agent.settings.packages = [letFateDecide];
}

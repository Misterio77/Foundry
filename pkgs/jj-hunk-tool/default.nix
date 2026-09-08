{
  lib,
  rustPlatform,
  fetchFromGitHub,
  jujutsu,
  makeWrapper,
}:
rustPlatform.buildRustPackage {
  pname = "jj-hunk-tool";
  version = "0.1.0-unstable-2026-07-19";

  src = fetchFromGitHub {
    owner = "mvzink";
    repo = "jj-hunk-tool";
    rev = "066ff0a6b959472c9bf6ae3a652ef6d367f27e1a";
    hash = "sha256-h/0vMBGrY9zBb6K+l4b+4Eos5Z16TA/3l8jkUzAIfyw=";
  };

  cargoHash = "sha256-qH/R0+urKZX3qtD6wt42hjgBOtu170HaR3SegRNlkh4=";

  nativeBuildInputs = [makeWrapper];
  nativeCheckInputs = [jujutsu];

  postFixup = ''
    wrapProgram $out/bin/jj-hunk-tool \
      --prefix PATH : ${lib.makeBinPath [jujutsu]}
  '';

  meta = {
    description = "Non-interactive hunk-level operations for Jujutsu";
    homepage = "https://github.com/mvzink/jj-hunk-tool";
    license = lib.licenses.mit;
    mainProgram = "jj-hunk-tool";
  };
}

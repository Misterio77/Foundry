{
  lib,
  stdenvNoCC,
  makeWrapper,
  tmux,
  wofi,
  handlr-regex,
  openssh,
  coreutils,
  gnugrep,
}:
stdenvNoCC.mkDerivation {
  pname = "tmux-picker";
  version = "1.0";
  src = ./tmux-picker.sh;

  nativeBuildInputs = [makeWrapper];

  dontUnpack = true;
  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    install -Dm755 $src $out/bin/tmux-picker
    wrapProgram $out/bin/tmux-picker --prefix PATH ':' "${lib.makeBinPath [tmux wofi handlr-regex openssh coreutils gnugrep]}"
  '';

  meta = {
    description = "A Wofi picker for local and connected SSH tmux sessions";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "tmux-picker";
  };
}

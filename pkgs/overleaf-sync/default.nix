{
  lib,
  writeShellApplication,
  coreutils,
  diffutils,
  findutils,
  git,
  jujutsu,
  rsync,
}:
(writeShellApplication {
  name = "overleaf-sync";
  runtimeInputs = [
    coreutils
    diffutils
    findutils
    git
    jujutsu
    rsync
  ];
  text = builtins.readFile ./overleaf-sync.sh;
})
// {
  meta = with lib; {
    description = "Synchronize local LaTeX projects with Overleaf";
    license = licenses.mit;
    mainProgram = "overleaf-sync";
    platforms = platforms.all;
  };
}

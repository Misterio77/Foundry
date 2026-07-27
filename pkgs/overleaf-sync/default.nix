{
  lib,
  writeShellApplication,
  coreutils,
  diffutils,
  findutils,
  git,
  jujutsu,
  pass,
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
    pass
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

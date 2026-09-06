{
  installShellFiles,
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "todomd";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.lock
      ./Cargo.toml
      ./src
      ./tests
    ];
  };

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [installShellFiles];

  postInstall = ''
    installShellCompletion --cmd todomd \
      --bash <($out/bin/todomd --generate-completion bash) \
      --fish <($out/bin/todomd --generate-completion fish) \
      --zsh <($out/bin/todomd --generate-completion zsh)
  '';

  meta = {
    description = "Edit vdir-backed VTODO lists as Markdown";
    homepage = "https://github.com/misterio77/Foundry/tree/main/projects/todomd";
    license = lib.licenses.bsd2;
    mainProgram = "todomd";
  };
}

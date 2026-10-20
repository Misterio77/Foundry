{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  curl,
  jansson,
  versionCheckHook,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "hax";

  # rev is the patch base; tarballs have no .git, so meson reports v0.6.1.
  version = "0.6.1";

  src = fetchFromGitHub {
    owner = "OleksandrChekhovskyi";
    repo = "hax";
    rev = "2273236304c8082e16ae38d08d172b9c71676a4d";
    hash = "sha256-hvCMCjAPdOwOibcrI5o8Zy/ggjlhhQYqsBteLZ0f9sI=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
  ];

  buildInputs = [
    curl
    jansson
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [versionCheckHook];

  meta = {
    description = "Minimalist, terminal-native coding agent written in C";
    homepage = "https://usehax.dev";
    changelog = "https://github.com/OleksandrChekhovskyi/hax/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "hax";
    platforms = lib.platforms.unix;
  };
})

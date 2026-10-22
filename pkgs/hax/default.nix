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

  # Fork of upstream; tarballs have no .git, so the version comes from meson.build.
  version = "0.6.1";

  src = fetchFromGitHub {
    owner = "Misterio77";
    repo = "hax";
    rev = "d4b634349a7eb8669c2e7982dd0734472e6ad139";
    hash = "sha256-e5mzenyZJ63gJyQvDoPtT+jO9kANxfUuYX7XbQyfUnU=";
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

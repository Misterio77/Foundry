{
  lib,
  stdenvNoCC,
  pkgsCross,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "sekiro-fps-unlock-and-more-native";
  version = "1.9.4";

  src = fetchFromGitHub {
    owner = "rootBrz";
    repo = "SekiroFPSUnlockAndMoreNative";
    rev = "8a14ea14b9afe178137b7a4ecc71e3773904cbb2";
    hash = "sha256-WU+4F1YVi6Bgb/W9pB9xfyhnsyTKl0YJUtqow35qFBc=";
  };

  nativeBuildInputs = [pkgsCross.mingwW64.stdenv.cc];
  strictDeps = true;
  enableParallelBuilding = true;

  makeFlags = [
    "CC=${pkgsCross.mingwW64.stdenv.cc.targetPrefix}gcc"
    "CXX=${pkgsCross.mingwW64.stdenv.cc.targetPrefix}g++"
  ];

  installPhase = ''
    runHook preInstall
    install -Dm644 build/d3dcompiler_43.dll "$out/d3dcompiler_43.dll"
    runHook postInstall
  '';

  meta = {
    description = "Sekiro FPS unlocker and fixes with settings in the game's own menu";
    homepage = "https://github.com/rootBrz/SekiroFPSUnlockAndMoreNative";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}

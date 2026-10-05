{
  fetchFromGitHub,
  gradle_8,
  jdk11,
  lib,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "runelite-hd";
  version = "1.5.2-unstable-2026-10-05";

  # PR #655: day/night cycle, not yet available through the Plugin Hub.
  src = fetchFromGitHub {
    owner = "3-X";
    repo = "RLHD";
    rev = "92d3cd815501ec37ab009a2d8651b68d3e7d62d0";
    hash = "sha256-1EHpFXAU8X7z8dlw6Um7JOvKZ4ygzlqi8bOAhJaFA/U=";
  };

  nativeBuildInputs = [
    gradle_8
    jdk11
  ];

  mitmCache = gradle_8.fetchDeps {
    pkg = finalAttrs.finalPackage;
    data = ./deps.json;
  };

  gradleFlags = [
    "-Dorg.gradle.java.home=${jdk11}"
    "--max-workers=1"
  ];
  gradleBuildTask = "jar";
  doCheck = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 build/libs/hd-*.jar $out/share/runelite/plugins/$pname.jar
    runHook postInstall
  '';

  meta = {
    description = "117 HD RuneLite plugin with the experimental day/night cycle";
    homepage = "https://github.com/117HD/RLHD/pull/655";
    license = lib.licenses.bsd2;
    platforms = lib.platforms.all;
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
    ];
  };
})

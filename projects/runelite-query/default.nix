{
  gradle_8,
  jdk11,
  lib,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "runelite-query";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./build.gradle
      ./settings.gradle
      ./runelite-plugin.properties
      ./src
    ];
  };

  nativeBuildInputs = [
    gradle_8
    jdk11
  ];

  mitmCache = gradle_8.fetchDeps {
    pkg = finalAttrs.finalPackage;
    data = ./deps.json;
  };

  # JDK 11.0.32 can crash in Gradle's parallel report workers while inflating
  # contended monitors; the package is small enough that serial workers are cheap.
  gradleFlags = [
    "-Dorg.gradle.java.home=${jdk11}"
    "--max-workers=1"
  ];
  gradleBuildTask = "jar";
  doCheck = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 build/libs/runelite-query-${finalAttrs.version}.jar \
      $out/share/runelite/sideloaded-plugins/runelite-query.jar
    runHook postInstall
  '';

  meta = {
    description = "Read-only local HTTP API exposing informational RuneLite state";
    homepage = "https://github.com/misterio77/Foundry/tree/main/projects/runelite-query";
    license = lib.licenses.bsd2;
    platforms = lib.platforms.all;
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
    ];
  };
})

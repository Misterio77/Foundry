{
  gradle_8,
  jdk11,
  lib,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "runelite-mcp";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../../projects/runelite-mcp;
    fileset = lib.fileset.unions [
      ../../projects/runelite-mcp/build.gradle
      ../../projects/runelite-mcp/settings.gradle
      ../../projects/runelite-mcp/src
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

  gradleFlags = ["-Dorg.gradle.java.home=${jdk11}"];
  gradleBuildTask = "jar";
  doCheck = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 build/libs/runelite-mcp-${finalAttrs.version}.jar \
      $out/share/runelite/sideloaded-plugins/runelite-mcp.jar
    runHook postInstall
  '';

  meta = {
    description = "Local MCP server exposing informational RuneLite state";
    homepage = "https://github.com/misterio77/Foundry/tree/main/projects/runelite-mcp";
    license = lib.licenses.bsd2;
    platforms = lib.platforms.all;
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
    ];
  };
})

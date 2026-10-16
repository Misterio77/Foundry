{
  fetchFromGitHub,
  gradle_8,
  jdk11,
  lib,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "runelite-hd";
  version = "1.5.2-unstable-2026-10-15";

  # Upstream master: includes the day/night cycle (PR #655, merged 2026-10-06),
  # which has not yet been released through the Plugin Hub.
  src = fetchFromGitHub {
    owner = "117HD";
    repo = "RLHD";
    rev = "5ec1c350b0fc49ef29e069959015ae439324c1d2";
    hash = "sha256-252cRxq0qDjWEFCfCTrtIPzVGf9cOnlcYdGc0tmvIi4=";
  };

  # The upstream stress test queues 1000 * 100 ms of busy-work. On small
  # builders this exceeds JobHandle's 10-second wait timeout, whose error
  # handler expects a plugin instance that the test fixture does not provide.
  # Keep parallel-job coverage, but bound total work to 3.2 seconds even with
  # a single worker. Only the test is changed; production code is untouched.
  postPatch = ''
    substituteInPlace src/test/java/rs117/hd/tests/JobSystemTests.java \
      --replace-fail 'int taskCount = 1000;' 'int taskCount = 32;'
  '';

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
    description = "117 HD RuneLite plugin, tracking upstream master for the day/night cycle";
    homepage = "https://github.com/117HD/RLHD";
    license = lib.licenses.bsd2;
    platforms = lib.platforms.all;
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
    ];
  };
})

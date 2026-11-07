{
  lib,
  stdenvNoCC,
  fetchurl,
}: let
  tool = name: archive: sha256:
    stdenvNoCC.mkDerivation {
      pname = name;
      version = "1.0.14";
      src = fetchurl {
        url = "https://github.com/stalwartlabs/${
          if name == "stalwart-cli"
          then "cli"
          else name
        }/releases/download/v1.0.14/${name}-x86_64-unknown-linux-musl.tar.${archive}";
        inherit sha256;
      };
      sourceRoot = "${name}-x86_64-unknown-linux-musl";
      dontConfigure = true;
      dontBuild = true;
      dontStrip = true;
      installPhase = ''
        runHook preInstall
        install -Dm755 ${name} "$out/bin/${name}"
        runHook postInstall
      '';
      meta = {
        description = "Stalwart ${name} management and migration tool";
        license = lib.licenses.agpl3Only;
        platforms = ["x86_64-linux"];
        mainProgram = name;
      };
    };
in {
  cli = tool "stalwart-cli" "xz" "c90824fe60b29d56c5a590baf321a30d422153f7aa64ac5f840d16f30895e59c";
  vandelay = tool "vandelay" "gz" "26667bde4e32fc2922ad20a59cf3042a9309d4cb511d0b86c72f88a1318ef532";
}

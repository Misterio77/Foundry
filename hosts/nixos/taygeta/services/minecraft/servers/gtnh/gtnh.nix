{
  lib,
  stdenvNoCC,
  fetchzip,
  jre_headless,
  groovy,
  makeWrapper,
  writeShellScript,
  ...
}: let
  # Groovy script to parse meta inf from jar
  readMetaInf = /* groovy */ ''
    import java.net.URL
    import java.io.File
    import java.util.jar.Attributes.Name

    jarPath = args[0]
    pathPrefix = args[1]
    jar = new URL("jar:file:" + new File(jarPath).getAbsolutePath()+ "!/")
    attributes =  jar.openConnection().getManifest().getMainAttributes()
    println(attributes.get(Name.MAIN_CLASS))
    println(attributes.get(Name.CLASS_PATH).split(' ').collect{"$pathPrefix/$it"}.join(':'))
  '';
in stdenvNoCC.mkDerivation {
  pname = "gt-new-horizons";
  version = "2.8.0";

  src = fetchzip {
    url = "https://downloads.gtnewhorizons.com/ServerPacks/GT_New_Horizons_2.8.0_Server_Java_17-25.zip";
    hash = "sha256-HH/Z3T6H3cDHFuPsxKSlJELGLL4Hc/5s2DZCxU+Txhs=";
    stripRoot = false;
  };

  nativeBuildInputs = [makeWrapper groovy];

  preStart = writeShellScript "gtnh-prestart" ''
    out=$1
    for name in "config" "serverutilities" "server.properties"; do
      if ! [[ -e "$name" ]]; then
        echo "$name missing. Copying it from $out/lib."
        cp -rL "$out/lib/$name" .
        chmod +w "$name" -R
      fi
    done
    if ! [[ -e "eula.txt" ]]; then
      echo "NOTICE: by running this software, you agree to https://account.mojang.com/documents/minecraft_eula"
      echo "eula=true" > eula.txt
    fi
  '';

  installPhase = ''
    mkdir $out
    ln -s $src $out/lib
    mainJar="$out/lib/lwjgl3ify-forgePatches.jar"
    # Get main_class and class_path from main jar
    { read main_class; read class_path; } < <(groovy -e ${lib.escapeShellArg readMetaInf} $mainJar $out/lib)
    # Add extra required jars to class_path
    class_path+="$(printf ':%s' $out/lib/mods/lwjgl3ify-*.jar)"
    # Collect mods and pass them as --mods. Has to be in runtime to get their path relative to PWD
    makeWrapper ${lib.getExe jre_headless} $out/bin/gt-new-horizons \
      --run "$preStart $out" \
      --run 'mods="$(find "$(realpath --relative-to="$PWD" '$out'/lib/mods)" -name "*.jar" | tr "\n" ",")"' \
      --append-flags "@$out/lib/java9args.txt -cp $mainJar:$class_path $main_class nogui --mods \"\$mods\""
  '';
}

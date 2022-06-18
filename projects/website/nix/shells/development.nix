{ mkShell, yq, openring, misterio-me, css-themes }: mkShell {
  inputsFrom = [ misterio-me ];
  buildInputs = [ yq openring ];
  shellHook = ''
    while [ ! -f flake.nix ]; do
      echo "Looking for flake.nix, going one directory up"
      cd ..
    done

    rm src/_includes/scheme-datalist.html 2> /dev/null
    rm src/assets/themes/* 2> /dev/null

    mkdir src/assets/themes -p
    ln -s ${css-themes}/list.html -T src/_includes/scheme-datalist.html
    ln -s ${css-themes}/*.css -t src/assets/themes/
  '';
}

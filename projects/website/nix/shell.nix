{ mkShell, yq, openring, main, themes }: mkShell {
  inputsFrom = [ main ];
  buildInputs = [ yq openring ];
  shellHook = ''
    while [ ! -f flake.nix ]; do
      echo "Looking for flake.nix, going one directory up"
      cd ..
    done

    rm _src/_includes/scheme-datalist.html 2> /dev/null
    rm _src/assets/themes/* 2> /dev/null

    mkdir _src/assets/themes -p
    ln -s ${themes}/list.html -T _src/_includes/scheme-datalist.html
    ln -s ${themes}/*.css -t _src/assets/themes/
  '';
}

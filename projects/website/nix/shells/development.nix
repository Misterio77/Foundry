{ mkShell, yq, openring, misterio-me, css-themes }: mkShell {
  inputsFrom = [ misterio-me ];
  buildInputs = [ yq openring ];
  shellHook = ''
    while [ ! -f flake.nix ]; do
      echo "Looking for flake.nix, going one directory up"
      cd ..
    done

    rm _main/_includes/scheme-datalist.html 2> /dev/null
    rm _main/assets/themes/* 2> /dev/null

    mkdir _main/assets/themes -p
    ln -s ${css-themes}/list.html -T _main/_includes/scheme-datalist.html
    ln -s ${css-themes}/*.css -t _main/assets/themes/
  '';
}

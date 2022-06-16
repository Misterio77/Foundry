{ stdenv, ruby, bundlerEnv, css-themes }:

let
  gems = bundlerEnv {
    name = "misterio-me-env";
    inherit ruby;
    gemdir = ./.;
  };
in
stdenv.mkDerivation {
  name = "misterio-me";
  src = ./.;

  JEKYLL_ENV = "production";

  buildInputs = [ gems ruby ];

  buildPhase = ''
    mkdir _main/assets/themes -p
    cp ${css-themes}/list.html _main/_includes/scheme-datalist.html
    cp -r ${css-themes}/*.css _main/assets/themes/
    ${gems}/bin/bundle exec jekyll build
  '';

  installPhase = ''
    mkdir -p $out
    cp -Tr _site $out/public
  '';
}

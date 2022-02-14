{ stdenv, jekyll, css-themes }:

stdenv.mkDerivation {
  name = "misterio-me";
  src = ./.;

  JEKYLL_ENV = "production" ;

  buildInputs = [ jekyll ];

  buildPhase = ''
    mkdir assets/themes -p
    cp ${css-themes}/list.html _includes/scheme-datalist.html
    cp -r ${css-themes}/*.css assets/themes/
    jekyll build
  '';

  installPhase = ''
    mkdir -p $out
    cp -Tr _site $out/public
  '';
}

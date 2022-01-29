{ stdenv, jekyll }:

stdenv.mkDerivation {
  name = "misterio-me";
  src = ./.;

  JEKYLL_ENV = "production" ;

  buildInputs = [ jekyll ];

  buildPhase = ''
    jekyll build
  '';
  installPhase = ''
    mkdir -p $out
    cp -Tr _site $out/public
  '';
}

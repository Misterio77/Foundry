{ stdenv, ruby, bundlerEnv }:

let gems = bundlerEnv {
  name = "website-env";
  inherit ruby;
  gemfile = ./Gemfile;
  lockfile = ./Gemfile.lock;
  gemset = ./gemset.nix;
};
in
stdenv.mkDerivation {
  name = "website";
  src = ./.;

  JEKYLL_ENV = "production";

  buildInputs = [ gems ruby ];

  buildPhase = ''
    ${gems}/bin/bundle exec jekyll build
  '';

  installPhase = ''
    mkdir -p $out
    cp -r _site -T $out/public
  '';
}

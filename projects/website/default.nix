with (import <nixpkgs> {});
let
  gems = bundlerEnv {
    name = "misterio-me";
    inherit ruby;
    gemdir = ./.;
  };
in stdenv.mkDerivation {
  name = "misterio-me";
  buildInputs = [gems ruby nodePackages.prettier];
}

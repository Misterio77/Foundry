{
  lib,
  pkg-config,
  hyprland,
  cmake,
  fetchFromGitHub,
  gnused,
}:
hyprland.stdenv.mkDerivation (final: {
  pname = "hyprbars";
  version = "0.56.0";

  src = "${fetchFromGitHub {
    owner = "hyprwm";
    repo = "hyprland-plugins";
    rev = "7644cecdb947060682891a0db2a0cdc5c0b9e704";
    hash = "sha256-piRpwar7VZI3YviYo0a/UMFz9+rLesfv3nRLGKxjVGg=";
  }}/hyprbars";
  buildInputs = [hyprland] ++ hyprland.buildInputs;
  nativeBuildInputs = [pkg-config cmake];

  postPatch = ''
    ${lib.getExe gnused} -i '/Initialized successfully/d' main.cpp
  '';

  meta = {
    inherit (hyprland.meta) platforms;
    license = lib.licenses.bsd3;
  };
})

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
  version = "0.57.0";

  src = "${fetchFromGitHub {
    owner = "hyprwm";
    repo = "hyprland-plugins";
    tag = "v${final.version}";
    hash = "sha256-y+V5RFJcjnV1+ZzImkfiSJ97iDIflanjP2OR9lemvTs=";
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

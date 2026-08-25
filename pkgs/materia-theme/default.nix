{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  sassc,
  gnome-shell,
  gnome-themes-extra,
  gdk-pixbuf,
  librsvg,
}:
stdenv.mkDerivation rec {
  pname = "materia-theme";
  version = "20210322";

  src = fetchFromGitHub {
    owner = "nana-4";
    repo = "materia-theme";
    rev = "v${version}";
    hash = "sha256-dHcwPTZFWO42wu1LbtGCMm2w/YHbjSUJnRKcaFllUbs=";
  };

  nativeBuildInputs = [
    meson
    ninja
    sassc
  ];
  buildInputs = [
    gnome-themes-extra
    gdk-pixbuf
    librsvg
  ];
  mesonFlags = ["-Dgnome_shell_version=${lib.versions.majorMinor gnome-shell.version}"];

  postInstall = ''
    rm $out/share/themes/*/COPYING
  '';

  meta = {
    description = "Material Design theme for GNOME/GTK based desktop environments";
    homepage = "https://github.com/nana-4/materia-theme";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.all;
  };
}

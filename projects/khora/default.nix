{
  lib,
  python3Packages,
  khal,
  gobject-introspection,
  gsettings-desktop-schemas,
  gtk4,
  libadwaita,
  wrapGAppsHook4,
}:
python3Packages.buildPythonApplication {
  pname = "khora";
  version = "0.1.0";
  pyproject = true;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./data
      ./README.md
      ./pyproject.toml
      ./khora
      ./tests
    ];
  };

  build-system = [python3Packages.setuptools];
  dependencies = [
    khal
    python3Packages.pygobject3
  ];

  nativeBuildInputs = [
    gobject-introspection
    wrapGAppsHook4
  ];
  buildInputs = [
    gtk4
    libadwaita
  ];
  nativeCheckInputs = [python3Packages.pytestCheckHook];

  shellHook = ''
    export XDG_DATA_DIRS="${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}:${gtk4}/share/gsettings-schemas/${gtk4.name}:$XDG_DATA_DIRS"
  '';

  postInstall = ''
    install -Dm644 data/rs.m7.Khora.desktop \
      $out/share/applications/rs.m7.Khora.desktop
    install -Dm644 data/rs.m7.Khora.svg \
      $out/share/icons/hicolor/scalable/apps/rs.m7.Khora.svg
  '';

  meta = {
    description = "Graphical calendar for local vdirs";
    homepage = "https://github.com/misterio77/Foundry/tree/main/projects/khora";
    license = lib.licenses.bsd2;
    mainProgram = "khora";
    platforms = lib.platforms.linux;
  };
}

{
  lib,
  fetchFromGitHub,
  python3Packages,
}:
python3Packages.buildPythonApplication {
  pname = "robohash";
  version = "2.0-unstable-2026-03-12";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "e1ven";
    repo = "Robohash";
    rev = "52cb1525d83306652b79ac440e94cdd45e22a43a";
    hash = "sha256-fMQ+neDyGyr0f6OwGRNPFtr6lTgMyLfEceyNTbr4g8Y=";
  };

  # Authentik validates image URLs with HEAD before returning them to clients.
  patches = [./head-localhost.patch];

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail '    "backgrounds/*/*",' '    "backgrounds/*/*",
    "templates/*",
    "static/*",
    "static/**/*",'
    printf '\n[project.scripts]\nrobohash = "robohash.webfront:main"\n' >> pyproject.toml
    cp ${./test_http.py} tests/test_http.py
  '';

  build-system = [python3Packages.setuptools];
  dependencies = with python3Packages; [pillow natsort tornado];
  nativeCheckInputs = [python3Packages.pytestCheckHook];
  pythonImportsCheck = ["robohash" "robohash.webfront"];

  meta = {
    description = "Deterministic avatar generator";
    homepage = "https://github.com/e1ven/Robohash";
    license = with lib.licenses; [mit cc-by-30 cc-by-40];
    mainProgram = "robohash";
  };
}

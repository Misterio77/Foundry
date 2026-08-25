{
  fetchFromGitHub,
  buildPythonPackage,
  dbus-python,
  setuptools,
}:
buildPythonPackage rec {
  pname = "lyrics-in-terminal";
  version = "1.5.0";

  src = fetchFromGitHub {
    owner = "jugran";
    repo = "lyrics-in-terminal";
    rev = version;
    hash = "sha256-61l4W7X66WHm1k/M/JM55dNj+mMh4R9ohKbByk9dIVA=";
  };

  propagatedBuildInputs = [dbus-python];

  doCheck = false;
  pyproject = true;
  build-system = [setuptools];

  patches = [./fix-config-in-build-phase.diff];
}

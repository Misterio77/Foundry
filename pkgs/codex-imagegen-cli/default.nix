{
  lib,
  fetchFromGitHub,
  python3Packages,
}:
python3Packages.buildPythonApplication {
  pname = "codex-imagegen-cli";
  version = "0.2.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "jdmnk";
    repo = "codex-imagegen-cli";
    rev = "bf126f9052723a93ed2dada138df08b66d10d560";
    hash = "sha256-ZnSDWmTCg5jONUz9VoMm51vNGL86nFp8Uya9ob6ezS4=";
  };

  # Upstream pins a newer hatchling, but does not require its newer features.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'hatchling>=1.32.0,<1.33' 'hatchling'
  '';

  build-system = [python3Packages.hatchling];
  dependencies = [python3Packages.pillow];

  nativeCheckInputs = [python3Packages.pytestCheckHook];
  disabledTestPaths = ["tests/test_live.py"];
  pythonImportsCheck = ["codex_imagegen_cli"];

  meta = {
    description = "Generate and edit images using Codex ChatGPT authentication";
    homepage = "https://github.com/jdmnk/codex-imagegen-cli";
    license = lib.licenses.asl20;
    mainProgram = "codex-imagegen";
  };
}

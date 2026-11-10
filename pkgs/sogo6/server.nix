{
  lib,
  fetchFromGitHub,
  fetchPypi,
  makeWrapper,
  python313Packages,
  radicale,
}: let
  python = python313Packages;
  authlib = python.authlib.overridePythonAttrs (_: {
    version = "1.9.5";
    # The PyPI distribution omits the upstream test directories.
    doCheck = false;
    src = fetchPypi {
      pname = "authlib";
      version = "1.9.5";
      hash = "sha256-PwMdXptkhgiekej38baPNidfMVHGZGDWUPyQ1CBUX9c=";
    };
  });
  flask-smorest = python.buildPythonPackage {
    pname = "flask-smorest";
    version = "0.47.0";
    pyproject = true;
    src = fetchPypi {
      pname = "flask_smorest";
      version = "0.47.0";
      hash = "sha256-pBXOfbPX5j3YVOsW1ZBHaG2/XTHEkT4kX6Vlf4jneI0=";
    };
    build-system = [python.flit-core];
    dependencies = with python; [apispec flask marshmallow webargs werkzeug];
    pythonImportsCheck = ["flask_smorest"];
  };
in
  python.buildPythonApplication rec {
    pname = "sogo6-server";
    version = "6.0.0-alpha2";
    pyproject = true;
    src = fetchFromGitHub {
      owner = "Alinto";
      repo = "SOGo6-server";
      rev = "v${version}";
      hash = "sha256-sYTMIvmCIPpq95hwsmsX/JLO4nvi++K8HwPLmjFLevA=";
    };
    patches = [./oidc.patch ./dav.patch ./identity.patch ./production.patch ./dav-production.patch ./dav-colors.patch];
    build-system = [python.poetry-core];
    nativeBuildInputs = [makeWrapper];
    pythonRemoveDeps = ["types-smorest" "pytest-mock"];
    dependencies = with python; [
      authlib
      flask-smorest
      argon2-cffi
      celery
      click
      cryptography
      flask
      flask-compress
      flask-cors
      gunicorn
      icalendar
      marshmallow
      mysql-connector
      passlib
      psycopg
      pydantic
      pydantic-settings
      pyjwt
      python-ldap
      redis
      requests
      sievelib
      yarl
    ];
    postInstall = ''
      makeWrapper ${python.python.interpreter} "$out/bin/sogo6-server" \
        --prefix PYTHONPATH : "${python.makePythonPath dependencies}:$out/${python.python.sitePackages}" \
        --add-flags "-m gunicorn app.run:app"
    '';
    nativeCheckInputs = with python; [pytestCheckHook pytest-mock pyyaml];
    enabledTestPaths = [
      "tests/test_module/test_auth/test_foundry_identity.py"
      "tests/test_module/test_auth/test_foundry_dav.py"
      "tests/test_module/test_auth/test_foundry_dav_capabilities.py"
      "tests/test_module/test_auth/test_foundry_runtime.py"
      "tests/test_module/test_auth/test_foundry_sogo_blueprint.py"
    ];
    preCheck = ''
      export RADICALE_TEST_SERVER=${radicale}/bin/radicale
      export SOGO_TEST_BLUEPRINT=${../../hosts/nixos/alcyone/services/authentik/sogo.yaml}
      export SOGO_P_REDIS_URL=redis://127.0.0.1:1/0
      export SOGO_P_VOUCHER_SECRET=00000000000000000000000000000000
      export SOGO_AES_ENC_KEY=11111111111111111111111111111111
      export SOGO_LOG_PATH="$TMPDIR/sogo-test.log"
    '';
    meta = {
      description = "SOGo 6 API with Foundry OIDC and direct-DAV integration";
      homepage = "https://github.com/Alinto/SOGo6-server";
      license = lib.licenses.gpl3Plus;
      mainProgram = "sogo6-server";
      platforms = lib.platforms.linux;
    };
  }

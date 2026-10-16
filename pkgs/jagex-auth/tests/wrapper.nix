{
  lib,
  makeDesktopItem,
  python3,
  runCommand,
  symlinkJoin,
  writeTextFile,
  jagex-auth,
}: let
  executable = writeTextFile {
    name = "jagex-auth-test-client";
    destination = "/bin/test-client";
    executable = true;
    text = ''
      #!${lib.getExe python3}
      import json, os, sys
      print(json.dumps({"args": sys.argv[1:], "session": os.environ["JX_SESSION_ID"], "name": os.environ["JX_DISPLAY_NAME"]}))
    '';
  };
  desktop = makeDesktopItem {
    name = "test-client";
    desktopName = "Test Client";
    exec = "test-client %U";
  };
  client = symlinkJoin {
    name = "jagex-auth-test-client";
    pname = "test-client";
    version = "1";
    paths = [executable desktop];
    meta.mainProgram = "test-client";
  };
  wrapped = jagex-auth.wrapLaunch client;
in
  runCommand "jagex-auth-wrapper-check" {} ''
    export HOME="$TMPDIR/home"
    export XDG_DATA_HOME="$HOME/.local/share"
    mkdir -p "$HOME"
    ${lib.getExe python3} - <<'PY'
    import json, os, pathlib, subprocess
    data = pathlib.Path(os.environ["XDG_DATA_HOME"]) / "jagex-auth"
    data.mkdir(parents=True, mode=0o700)
    credentials = data / "credentials.json"
    name = 'A Name $(false) `false` " \\ 日本語'
    credentials.write_text(json.dumps({
        "version": 1, "JX_SESSION_ID": "synthetic-session",
        "JX_CHARACTER_ID": "character", "JX_DISPLAY_NAME": name,
    }))
    credentials.chmod(0o600)
    # Installed entry points must not import packages from the working directory.
    shadow = pathlib.Path(os.environ["HOME"]) / "shadow-cwd"
    module = shadow / "jagex_auth"
    module.mkdir(parents=True)
    (module / "__init__.py").write_text('raise SystemExit("untrusted cwd package imported")\n')
    (module / "__main__.py").write_text('raise SystemExit("untrusted cwd module executed")\n')
    help_result = subprocess.run(["${jagex-auth}/bin/jagex-auth", "--help"], cwd=shadow, capture_output=True, text=True)
    assert help_result.returncode == 0, help_result.stderr
    assert "authorize" in help_result.stdout
    args = ["argument with spaces", "--flag", "$(false)"]
    result = subprocess.run(["${wrapped}/bin/test-client", *args], cwd=shadow, check=True, capture_output=True, text=True)
    assert json.loads(result.stdout) == {"args": args, "session": "synthetic-session", "name": name}
    desktop = pathlib.Path("${wrapped}/share/applications/test-client.desktop").read_text()
    assert "Exec=test-client %U" in desktop
    # Wrapper targets the original client, not itself; original output stays intact.
    wrapper = pathlib.Path("${wrapped}/bin/test-client").read_text()
    assert "${client}/bin/test-client" in wrapper
    assert "credentials.properties" not in wrapper
    assert "synthetic-session" not in wrapper
    assert pathlib.Path("${client}/bin/test-client").read_text().startswith("#!")
    credentials.unlink()
    result = subprocess.run(["${wrapped}/bin/test-client"], capture_output=True, text=True)
    assert result.returncode != 0 and "jagex-auth authorize" in result.stderr
    PY
    touch "$out"
  ''

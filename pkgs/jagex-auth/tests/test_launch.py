"""Credential and exec tests use only synthetic secrets in temporary directories."""

import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import jagex_auth as auth


class LaunchTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.data = self.root / "jagex-auth"
        for name, value in {
            "DATA_DIR": self.data,
            "CREDENTIALS_FILE": self.data / "credentials.json",
        }.items():
            self.enterContext(patch.object(auth, name, value))
        self.env = {**os.environ, "HOME": str(self.root), "XDG_DATA_HOME": str(self.root)}
        self.cli = str(Path(auth.__file__).with_name("jagex-auth.py"))
        self.account = {"accountId": "character", "displayName": "A Name"}

    def run_cli(self, *args):
        return subprocess.run(
            [sys.executable, self.cli, "launch", "--", *args],
            env=self.env, capture_output=True, text=True, timeout=10,
        )

    def test_literal_credentials_and_argv(self):
        value = "日本語 $(touch INJECTED) `touch INJECTED` ' \" \\ \n"
        self.account["displayName"] = value
        auth.write_credentials("synthetic-session", self.account)
        result = self.run_cli(sys.executable, "-c", "import json,os,sys; print(json.dumps([dict(os.environ),sys.argv[1:]]))", "a b", "--flag", "$(false)")
        self.assertEqual(result.returncode, 0, result.stderr)
        env, argv = json.loads(result.stdout)
        self.assertEqual(env["JX_DISPLAY_NAME"], value)
        self.assertEqual(env["JX_SESSION_ID"], "synthetic-session")
        self.assertEqual(env["JX_CHARACTER_ID"], "character")
        self.assertEqual(env["HOME"], str(self.root))
        self.assertEqual(argv, ["a b", "--flag", "$(false)"])

    def test_saved_values_override_inherited_credentials(self):
        auth.write_credentials("saved", self.account)
        with patch.dict(os.environ, {"JX_SESSION_ID": "inherited"}), patch.object(auth.os, "execvpe") as execute:
            auth.launch(argparse.Namespace(command=["--", "client", "arg"]))
        executable, argv, env = execute.call_args.args
        self.assertEqual(executable, "client")
        self.assertEqual(argv, ["client", "arg"])
        self.assertEqual(env["JX_SESSION_ID"], "saved")

    def test_missing_credentials_fail_without_launching(self):
        result = self.run_cli(sys.executable, "-c", "print('LAUNCHED')")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("LAUNCHED", result.stdout)
        self.assertIn("jagex-auth authorize", result.stderr)

    def test_invalid_schema(self):
        auth.ensure_data_dir()
        for value in ({}, [], {"version": True}, {"version": 2}, {
            "version": 1, "JX_SESSION_ID": "s", "JX_CHARACTER_ID": "c", "JX_DISPLAY_NAME": "\0",
        }):
            with self.subTest(value=value):
                auth.atomic_write_private(auth.CREDENTIALS_FILE, json.dumps(value))
                with self.assertRaisesRegex(SystemExit, "authorize"):
                    auth.read_credentials()

    def test_rejects_unsafe_files(self):
        auth.write_credentials("s", self.account)
        auth.CREDENTIALS_FILE.chmod(0o644)
        with self.assertRaisesRegex(SystemExit, "unsafe"):
            auth.read_credentials()
        auth.CREDENTIALS_FILE.unlink()
        target = self.root / "target"
        target.write_text("{}")
        auth.CREDENTIALS_FILE.symlink_to(target)
        with self.assertRaisesRegex(SystemExit, "unsafe"):
            auth.read_credentials()
        auth.CREDENTIALS_FILE.unlink()
        os.mkfifo(auth.CREDENTIALS_FILE, 0o600)
        with self.assertRaisesRegex(SystemExit, "unsafe"):
            auth.read_credentials()

    def test_atomic_private_write_and_failure_preserves_previous(self):
        auth.write_credentials("old", self.account)
        old = auth.CREDENTIALS_FILE.read_bytes()
        real_replace = Path.replace

        def inspect_replace(path, target):
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertNotEqual(path, auth.CREDENTIALS_FILE)
            raise OSError("simulated failure")

        with patch.object(Path, "replace", inspect_replace), self.assertRaises(SystemExit):
            auth.write_credentials("new", self.account)
        self.assertEqual(auth.CREDENTIALS_FILE.read_bytes(), old)
        self.assertEqual(list(self.data.iterdir()), [auth.CREDENTIALS_FILE])
        self.assertIs(Path.replace, real_replace)

    def test_exit_status_and_signals(self):
        auth.write_credentials("s", self.account)
        self.assertEqual(self.run_cli(sys.executable, "-c", "raise SystemExit(42)").returncode, 42)
        result = self.run_cli(sys.executable, "-c", "import os,signal; os.kill(os.getpid(), signal.SIGTERM)")
        self.assertEqual(result.returncode, -signal.SIGTERM)

    def test_launch_errors(self):
        self.assertIn("Usage:", self.run_cli().stderr)
        auth.write_credentials("s", self.account)
        self.assertEqual(self.run_cli(str(self.root / "missing")).returncode, 127)
        target = self.root / "not-executable"
        target.write_text("not executable")
        self.assertEqual(self.run_cli(str(target)).returncode, 126)


if __name__ == "__main__":
    unittest.main()

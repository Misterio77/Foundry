import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("prepare", Path(__file__).with_name("seerr-prepare.py"))
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class PrepareTest(unittest.TestCase):
    def test_configuration_and_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / "config"
            config.mkdir()
            original = {
                "main": {"localLogin": True, "mediaServerLogin": True},
                "radarr": [{"hostname": "localhost"}],
                "oidc": {"providers": [{"slug": "another"}]},
            }
            (config / "settings.json").write_text(json.dumps(original))
            (config / "db").mkdir()
            (config / "db" / "db.sqlite3").write_bytes(b"original database")
            secret = root / "secret"
            secret.write_text("test-secret\n")
            prepare.configure(config, secret)
            result = json.loads((config / "settings.json").read_text())
            self.assertTrue(result["main"]["oidcLogin"])
            self.assertTrue(result["main"]["localLogin"])
            self.assertTrue(result["main"]["mediaServerLogin"])
            self.assertEqual(result["radarr"], original["radarr"])
            self.assertEqual(result["oidc"]["providers"][0], {"slug": "another"})
            self.assertEqual(result["oidc"]["providers"][1]["clientSecret"], "test-secret")
            backup = root / "config.pre-oidc"
            self.assertEqual(json.loads((backup / "settings.json").read_text()), original)
            self.assertEqual((backup / "db" / "db.sqlite3").read_bytes(), b"original database")
            self.assertEqual((config / "settings.json").stat().st_mode & 0o777, 0o600)
            (config / "db" / "db.sqlite3").write_bytes(b"migrated database")
            secret.write_text("rotated-secret")
            prepare.configure(config, secret)
            result = json.loads((config / "settings.json").read_text())
            self.assertEqual(len(result["oidc"]["providers"]), 2)
            self.assertEqual(result["oidc"]["providers"][1]["clientSecret"], "rotated-secret")
            self.assertEqual((backup / "db" / "db.sqlite3").read_bytes(), b"original database")

    def test_empty_secret_does_not_change_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / "config"
            config.mkdir()
            original = '{"main": {}}'
            (config / "settings.json").write_text(original)
            secret = root / "secret"
            secret.write_text("\n")
            with self.assertRaises(ValueError):
                prepare.configure(config, secret)
            self.assertEqual((config / "settings.json").read_text(), original)
            self.assertFalse((root / "config.pre-oidc").exists())


if __name__ == "__main__":
    unittest.main()

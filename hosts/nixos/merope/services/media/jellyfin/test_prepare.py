import json
import sqlite3
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from prepare import check_identity_map, update_branding

ASSETS = Path(__file__).parent
USER_ID = "00000000-0000-0000-0000-000000000001"
ENTRY = {
    "ProviderId": "authentik",
    "Subject": "subject-1",
    "UserId": USER_ID,
    "Username": "existing-user",
}


class PrepareTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "data").mkdir()
        self.mapping = (
            self.root
            / "plugins/configurations/Jellyfin.Plugin.OIDC.UserProviderMap.json"
        )
        self.mapping.parent.mkdir(parents=True)
        self.db = sqlite3.connect(self.root / "data/jellyfin.db")
        self.addCleanup(self.db.close)
        self.db.execute("CREATE TABLE Users (Id TEXT, AuthenticationProviderId TEXT)")
        self.db.execute(
            "INSERT INTO Users VALUES (?,?)",
            (USER_ID, "Jellyfin.Plugin.OIDC.Auth.OidcAuthProvider"),
        )
        self.db.commit()
        self.mapping.write_text(json.dumps([ENTRY]))

    def test_bound_oidc_user_is_accepted(self):
        check_identity_map(self.root)

    def test_lost_or_invalid_bindings_are_rejected(self):
        cases = [
            None,
            "{bad",
            "null",
            "[]",
            json.dumps([ENTRY, ENTRY]),
            json.dumps([dict(ENTRY, ProviderId="other")]),
            json.dumps([dict(ENTRY, UserId="not-a-uuid")]),
            json.dumps([dict(ENTRY, Subject="")]),
            json.dumps([dict(ENTRY, UserId="00000000-0000-0000-0000-000000000002")]),
        ]
        for content in cases:
            with self.subTest(content=content):
                if content is None:
                    self.mapping.unlink(missing_ok=True)
                else:
                    self.mapping.write_text(content)
                with self.assertRaises((SystemExit, ValueError)):
                    check_identity_map(self.root)

    def test_local_and_null_providers_are_rejected(self):
        for provider in ("local", None):
            with self.subTest(provider=provider):
                self.db.execute(
                    "UPDATE Users SET AuthenticationProviderId = ?", (provider,)
                )
                self.db.commit()
                with self.assertRaises(SystemExit):
                    check_identity_map(self.root)

    def test_branding_is_idempotent_and_preserves_customization(self):
        config_dir = self.root / "config"
        config_dir.mkdir()
        branding = config_dir / "branding.xml"
        branding.write_text(
            "<BrandingOptions><LoginDisclaimer>Existing text\n"
            "&lt;!-- foundry-oidc:start --&gt;old button&lt;!-- foundry-oidc:end --&gt;"
            "</LoginDisclaimer><CustomCss>.existing {color:red;}\n"
            "/* foundry-oidc:start */ old css /* foundry-oidc:end */"
            "</CustomCss></BrandingOptions>"
        )
        for _ in range(2):
            update_branding(config_dir, ASSETS / "login.html", ASSETS / "login.css")
            current = branding.read_bytes()
            if _ == 0:
                initial = current
            else:
                self.assertEqual(current, initial)
        tree = ET.parse(branding)
        html = tree.findtext("LoginDisclaimer")
        css = tree.findtext("CustomCss")
        self.assertTrue(html.startswith("Existing text"))
        self.assertTrue(css.startswith(".existing {color:red;}"))
        self.assertNotIn("old button", html)
        self.assertNotIn("old css", css)
        self.assertEqual(html.count("foundry-oidc:start"), 1)
        self.assertEqual(css.count("foundry-oidc:start"), 1)

    def test_branding_can_be_created(self):
        config_dir = self.root / "new-config"
        update_branding(config_dir, ASSETS / "login.html", ASSETS / "login.css")
        tree = ET.parse(config_dir / "branding.xml")
        self.assertIn("Entrar com Gablogin", tree.findtext("LoginDisclaimer"))
        self.assertIn("#loginPage .btnManual", tree.findtext("CustomCss"))


if __name__ == "__main__":
    unittest.main()

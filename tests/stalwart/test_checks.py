import contextlib
import importlib.util
import io
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


def load(name):
    spec = importlib.util.spec_from_file_location(
        name, Path(__file__).with_name(name + ".py")
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


public = load("public-check")
restore = load("restore-check")


class TokenFileTests(unittest.TestCase):
    def test_private_raw_and_json_tokens(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "token"
            path.touch(mode=0o600)
            for text in ("test-token\n", '{"access_token":"test-token"}'):
                path.write_text(text)
                self.assertEqual(public.load_token(path), "test-token")

    def test_public_file_and_header_injection_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "token"
            path.write_text("test-token")
            path.chmod(0o644)
            with self.assertRaises(ValueError):
                public.load_token(path)
            path.chmod(0o600)
            path.write_text("test-token\r\nHeader: injected")
            with self.assertRaises(ValueError):
                public.load_token(path)

    def test_malformed_input_is_not_logged(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "token"
            path.touch(mode=0o600)
            path.write_text('{"access_token":"do-not-log-this"')
            output = io.StringIO()
            with (
                patch.object(
                    sys, "argv", ["public-check.py", "--token-file", str(path)]
                ),
                contextlib.redirect_stderr(output),
            ):
                self.assertEqual(public.main(), 1)
            self.assertEqual(
                json.loads(output.getvalue()), {"error": "JSONDecodeError"}
            )
            self.assertNotIn("do-not-log-this", output.getvalue())


class SafetyTests(unittest.TestCase):
    def test_smtp_ingress_uses_verified_starttls_without_delivery(self):
        with (
            patch.object(public.socket, "create_connection") as connect,
            patch.object(public.smtplib, "SMTP") as smtp,
        ):
            client = smtp.return_value
            client.getreply.return_value = (220, b"ready")
            client.ehlo.return_value = (250, b"ready")
            client.has_extn.side_effect = lambda name: name == "starttls"
            self.assertIs(public.smtp("192.0.2.1", 25), client)
            connect.assert_called_once_with(("192.0.2.1", 25), public.TIMEOUT)
            client.starttls.assert_called_once_with(context=public.TLS)
            client.data.assert_not_called()
            client.sendmail.assert_not_called()
            self.assertEqual(client._host, public.HOST)

    def test_restore_probe_refuses_host_network(self):
        with (
            patch.object(restore.os, "readlink", return_value="net:[host]"),
            self.assertRaisesRegex(RuntimeError, "private network"),
        ):
            restore.probe(None)

    def test_managed_fields_are_not_overwritten_through_api(self):
        requests = []

        def response(request, timeout):
            requests.append(request.full_url)
            body = (
                {"methodResponses": [["Email/query", {"ids": ["fixture"]}, "probe"]]}
                if request.full_url.endswith("/jmap/")
                else {"data": {}}
            )
            return io.BytesIO(json.dumps(body).encode())

        args = SimpleNamespace(
            probe="index",
            fields_configured=True,
            account="contato@lumis.cards",
            account_id="c",
            message_id="lumis-mx-fixture-public@lumis.cards",
        )
        with (
            patch.object(
                restore.os, "readlink", side_effect=["net:[fixture]", "net:[host]"]
            ),
            patch.object(restore.Path, "read_text", return_value="test-password"),
            patch.object(restore.urllib.request, "urlopen", side_effect=response),
        ):
            self.assertTrue(restore.probe(args)["header_after_explicit_fields"])
        self.assertFalse(
            any("/api/settings" in url or "/api/reload" in url for url in requests)
        )
        self.assertTrue(any("/api/store/reindex/" in url for url in requests))

    def test_fixture_and_nix_field_sets_match(self):
        config = (
            Path(__file__).resolve().parents[2]
            / "hosts/nixos/asterope/services/stalwart.nix"
        )
        fields = re.search(
            r"search-index\.email\.fields = \[(.*?)\];", config.read_text(), re.DOTALL
        ).group(1)
        self.assertEqual(re.findall(r'"([a-z-]+)"', fields), restore.EMAIL_FIELDS)
        self.assertEqual(len(restore.EMAIL_FIELDS), 12)


if __name__ == "__main__":
    unittest.main()

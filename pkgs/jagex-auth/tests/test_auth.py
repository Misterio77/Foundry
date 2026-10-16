"""Offline characterization tests; security hardening adds stricter cases later."""

import base64
import contextlib
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import urllib.error
import urllib.parse

import jagex_auth as auth


def token(payload):
    encoded = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")
    return f"header.{encoded}.signature"


class AuthTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.data = Path(self.temporary.name) / "jagex-auth"
        for name, value in {
            "DATA_DIR": self.data,
            "CALLBACK_FILE": self.data / "auth-callback-url",
            "CREDENTIALS_FILE": self.data / "credentials.json",
        }.items():
            patcher = patch.object(auth, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        # Fail closed if a test accidentally reaches a real browser or network.
        for target in ("urllib.request.urlopen", "webbrowser.open"):
            patcher = patch(target, side_effect=AssertionError(f"Unexpected external I/O: {target}"))
            patcher.start()
            self.addCleanup(patcher.stop)
        self.output = io.StringIO()
        self.enterContext(contextlib.redirect_stderr(self.output))

    def callback(self, **params):
        return "rshub://auth/callback#" + urllib.parse.urlencode(params)

    def test_auth_url_binds_state_nonce_and_client(self):
        parsed = urllib.parse.urlparse(auth.make_auth_url("state", "nonce"))
        self.assertEqual(f"{parsed.scheme}://{parsed.netloc}{parsed.path}", auth.AUTH_ENDPOINT)
        params = urllib.parse.parse_qs(parsed.query)
        self.assertEqual(params["state"], ["state"])
        self.assertEqual(params["nonce"], ["nonce"])
        self.assertEqual(params["client_id"], [auth.CLIENT_ID])
        self.assertEqual(params["redirect_uri"], [auth.REDIRECT_URI])
        self.assertEqual(params["response_type"], ["id_token"])

    def test_callback_and_manual_success_url(self):
        for url in (
            self.callback(state="expected", id_token="token"),
            auth.REDIRECT_URI + "#state=expected&id_token=token",
        ):
            self.assertEqual(auth.authentication_params(url, "expected")["id_token"], "token")

    def test_state_mismatch(self):
        with self.assertRaisesRegex(SystemExit, "state mismatch"):
            auth.authentication_params(self.callback(state="wrong"), "expected")

    def test_invalid_callback_origins(self):
        for url in ("https://evil.example/#state=s", "rshub://evil/callback", "rshub://auth/wrong"):
            with self.subTest(url=url), self.assertRaises(SystemExit):
                auth.authentication_params(url, "s")

    def test_decode_payload_is_not_signature_verification(self):
        payload = {"nonce": "n", "sub": "s", "nickname": "name"}
        self.assertEqual(auth.decode_jwt_payload(token(payload)), payload)
        for value in ("bad", "a.!.b", token([1, 2])):
            with self.subTest(value=value), self.assertRaises(SystemExit):
                auth.decode_jwt_payload(value)

    def test_request_json_serializes_request(self):
        with patch("urllib.request.urlopen", return_value=io.BytesIO(b'{"ok": true}')) as request:
            self.assertEqual(auth.request_json("https://test.invalid", method="POST", body={"x": 1}), {"ok": True})
        args, kwargs = request.call_args
        self.assertEqual(args[0].method, "POST")
        self.assertEqual(json.loads(args[0].data), {"x": 1})
        self.assertEqual(kwargs["timeout"], 30)

    def test_network_and_json_failures(self):
        for error in (urllib.error.URLError("offline"), TimeoutError()):
            with patch("urllib.request.urlopen", side_effect=error), self.assertRaises(SystemExit):
                auth.request_json("https://test.invalid")
        for body in (b"not-json", b"null", b"123"):
            with patch("urllib.request.urlopen", return_value=io.BytesIO(body)), self.assertRaises(SystemExit):
                auth.request_json("https://test.invalid")

    def test_session_and_accounts(self):
        with patch.object(auth, "request_json", return_value={"sessionId": "session"}) as request:
            self.assertEqual(auth.get_game_session("id"), "session")
            request.assert_called_once_with(auth.SESSION_ENDPOINT, method="POST", body={"idToken": "id"})
        accounts = [{"accountId": "character", "displayName": "Name"}]
        with patch.object(auth, "request_json", return_value=accounts) as request:
            self.assertEqual(auth.get_accounts("session"), accounts)
            request.assert_called_once_with(auth.ACCOUNTS_ENDPOINT, headers={"Authorization": "Bearer session"})
        for value in (None, {}, [], {"sessionId": ""}):
            with patch.object(auth, "request_json", return_value=value), self.assertRaises(SystemExit):
                auth.get_game_session("id")
        for value in ({}, []):
            with patch.object(auth, "request_json", return_value=value), self.assertRaises(SystemExit):
                auth.get_accounts("session")

    def test_character_selection(self):
        accounts = [{"accountId": "a"}, {"accountId": "b"}]
        self.assertEqual(auth.choose_account(accounts[:1]), accounts[0])
        with patch("builtins.input", side_effect=["bad", "0", "3", "2"]):
            self.assertEqual(auth.choose_account(accounts), accounts[1])

    def test_credentials_private_and_replaced(self):
        account = {"accountId": "character", "displayName": "A Name"}
        auth.write_credentials("old", account)
        auth.write_credentials("new", account)
        self.assertEqual(stat.S_IMODE(self.data.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(auth.CREDENTIALS_FILE.stat().st_mode), 0o600)
        contents = auth.CREDENTIALS_FILE.read_text()
        self.assertEqual(json.loads(contents)["JX_SESSION_ID"], "new")
        self.assertNotIn("old", contents)
        self.assertEqual(list(self.data.iterdir()), [auth.CREDENTIALS_FILE])
        with self.assertRaises(SystemExit):
            auth.write_credentials("session", {"accountId": "missing-name"})
        self.assertEqual(auth.CREDENTIALS_FILE.read_text(), contents)

    def test_callback_delivery_and_consumption(self):
        url = self.callback(state="s", id_token="id")
        auth.handle_url(type("Args", (), {"url": url})())
        self.assertEqual(stat.S_IMODE(auth.CALLBACK_FILE.stat().st_mode), 0o600)
        self.assertEqual(auth.wait_for_authentication(), url)
        self.assertFalse(auth.CALLBACK_FILE.exists())

    def test_authorize_flow(self):
        payload = {"nonce": "nonce", "sub": "subject", "nickname": "User"}
        account = {"accountId": "character", "displayName": "Name"}
        with (
            patch.object(auth.secrets, "token_urlsafe", side_effect=["state", "nonce"]),
            patch.object(auth, "open_browser") as browser,
            patch.object(auth, "wait_for_authentication", return_value=self.callback(state="state", id_token=token(payload))),
            patch.object(auth, "get_game_session", return_value="session"),
            patch.object(auth, "get_accounts", return_value=[account]),
            patch.object(auth, "write_credentials") as write,
        ):
            auth.authorize(None)
        browser.assert_called_once_with(auth.make_auth_url("state", "nonce"))
        write.assert_called_once_with("session", account)

    def test_nonce_mismatch_does_not_exchange_or_write(self):
        auth.ensure_data_dir()
        auth.CREDENTIALS_FILE.write_text("existing credentials")
        with (
            patch.object(auth.secrets, "token_urlsafe", side_effect=["state", "nonce"]),
            patch.object(auth, "open_browser"),
            patch.object(auth, "wait_for_authentication", return_value=self.callback(state="state", id_token=token({"nonce": "wrong"}))),
            patch.object(auth, "get_game_session") as exchange,
            self.assertRaisesRegex(SystemExit, "nonce mismatch"),
        ):
            auth.authorize(None)
        exchange.assert_not_called()
        self.assertEqual(auth.CREDENTIALS_FILE.read_text(), "existing credentials")

    def test_entry_point_help_without_credentials(self):
        result = subprocess.run(
            [sys.executable, "-m", "jagex_auth", "--help"],
            env={
                **os.environ,
                "HOME": self.temporary.name,
                "XDG_DATA_HOME": self.temporary.name,
                "PYTHONPATH": str(Path(auth.__file__).parent.parent),
            },
            cwd=self.temporary.name,
            capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("authorize", result.stdout)
        self.assertIn("handle-url", result.stdout)
        self.assertFalse(self.data.exists())


if __name__ == "__main__":
    unittest.main()

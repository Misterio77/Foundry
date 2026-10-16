"""Offline token, callback, race, timeout, and cancellation regression tests."""

import argparse
from email.message import Message
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import termios
import time
import unittest
from unittest.mock import patch
import urllib.error
import urllib.request
import urllib.response

import jagex_auth as auth
import test_auth as fixtures
from test_auth import encode_token, token


class HardeningTests(unittest.TestCase):
    setUp = fixtures.AuthTests.setUp
    callback = fixtures.AuthTests.callback

    def handle(self, url):
        auth.handle_url(argparse.Namespace(url=url))

    def test_inconsistent_unverified_claims(self):
        changes = [
            {"iss": "https://evil.invalid/"}, {"aud": "wrong"},
            {"exp": int(time.time()) - 120}, {"iat": int(time.time()) + 120},
            {"exp": None}, {"iat": True}, {"nbf": "0"},
            {"nonce": "wrong"}, {"nonce": None},
            {"sub": ""}, {"nickname": []}, {"azp": "wrong"},
            {"aud": [auth.CLIENT_ID, "other"]},
        ]
        for claims in changes:
            with self.subTest(claims=claims), self.assertRaises(SystemExit):
                auth.decode_id_token(token(claims), "nonce")

    def test_missing_required_claims(self):
        for claim in ("exp", "iat", "sub", "iss", "aud", "nonce"):
            value = auth.decode_id_token(token(), "nonce")
            del value[claim]
            with self.subTest(claim=claim), self.assertRaises(SystemExit):
                auth.decode_id_token(encode_token(value), "nonce")

    def test_decoding_is_not_signature_verification_and_never_fetches_keys(self):
        # An arbitrary signature passes local consistency checks, not login.
        encoded = token(headers={"alg": "RS256", "kid": "unknown", "jku": "https://evil.invalid/"})
        with patch.object(auth, "request_json") as request:
            self.assertEqual(auth.decode_id_token(encoded, "nonce")["sub"], "subject")
        request.assert_not_called()

    def test_server_rejection_or_failed_character_listing_never_saves_login(self):
        auth.write_credentials("existing", {"accountId": "c", "displayName": "Name"})
        before = auth.CREDENTIALS_FILE.read_bytes()
        id_token = token({"nickname": "UNTRUSTED"})
        for failed_step in ("session", "characters"):
            with (
                patch.object(auth.secrets, "token_urlsafe", side_effect=["state", "nonce"]),
                patch.object(auth, "open_browser"),
                patch.object(auth, "wait_for_authentication", return_value=self.callback(state="state", id_token=id_token)),
                patch.object(auth, "get_game_session", side_effect=SystemExit("rejected") if failed_step == "session" else None, return_value="session") as exchange,
                patch.object(auth, "get_accounts", side_effect=SystemExit("rejected")) as accounts,
                patch.object(auth, "write_credentials") as write,
                self.assertRaises(SystemExit),
            ):
                auth.authorize(None)
            exchange.assert_called_once_with(id_token)
            if failed_step == "session":
                accounts.assert_not_called()
            else:
                accounts.assert_called_once_with("session")
            write.assert_not_called()
            self.assertEqual(auth.CREDENTIALS_FILE.read_bytes(), before)
            self.assertNotIn("Authenticated", self.output.getvalue())
            self.assertNotIn("UNTRUSTED", self.output.getvalue())

    def test_strict_urls_and_parameters(self):
        valid = self.callback(state="s", id_token="id")
        for value in (
            token(), valid + "&state=s", valid + "&id_token=other",
            valid.replace("rshub://auth", "rshub://user@auth"),
            valid.replace("/callback", "/callback?query=1"),
            valid.replace("/callback", "/callback/"),
            auth.REDIRECT_URI.replace("/en-GB/", "/wrong/") + "#state=s&id_token=id",
            valid + "\n", valid + "&broken", valid + "&x=%FF",
            valid.replace("state=s", "state=%C3%A9"),
            valid.replace("state=s", "state=é"),
            self.callback(state="s", error="access_denied"),
            self.callback(state="s"), "x" * (auth.MAX_CALLBACK + 1),
        ):
            with self.subTest(value=value[:70]), self.assertRaises(SystemExit):
                auth.authentication_params(value, "s")

    def test_unsolicited_stale_mismatched_and_duplicate_callbacks(self):
        with self.assertRaisesRegex(SystemExit, "No active"):
            self.handle(self.callback(state="s", id_token="id"))
        auth.atomic_write_private(auth.PENDING_FILE, json.dumps({"state": "s", "expires": time.time() + 300}))
        with self.assertRaisesRegex(SystemExit, "No active"):
            self.handle(self.callback(state="s", id_token="id"))
        with auth.authorization_attempt() as (state, _):
            with self.assertRaisesRegex(SystemExit, "state mismatch"):
                self.handle(self.callback(state="wrong", id_token="id"))
            self.assertFalse(auth.CALLBACK_FILE.exists())
            valid = self.callback(state=state, id_token="first")
            self.handle(valid)
            with self.assertRaisesRegex(SystemExit, "already"):
                self.handle(self.callback(state=state, id_token="second"))
            self.assertEqual(auth.read_private_json(auth.CALLBACK_FILE)["url"], valid)
            self.assertEqual(auth.wait_for_authentication(timeout=1), valid)
            with self.assertRaisesRegex(SystemExit, "already"):
                self.handle(valid)

    def test_expired_pending_and_callback_permissions(self):
        with auth.authorization_attempt() as (state, _):
            auth.atomic_write_private(auth.PENDING_FILE, json.dumps({"state": state, "expires": time.time() - 1}))
            with self.assertRaisesRegex(SystemExit, "expired"):
                self.handle(self.callback(state=state, id_token="id"))
        self.assertFalse(auth.PENDING_FILE.exists())
        self.assertFalse(auth.CALLBACK_FILE.exists())
        self.assertEqual(auth.AUTH_LOCK.stat().st_mode & 0o777, 0o600)
        self.assertEqual(auth.CALLBACK_LOCK.stat().st_mode & 0o777, 0o600)

    def test_concurrent_authorizers_preserve_pending(self):
        with auth.authorization_attempt() as (state, _):
            before = auth.PENDING_FILE.read_bytes()
            with self.assertRaisesRegex(SystemExit, "already running"):
                with auth.authorization_attempt():
                    self.fail("Second login was allowed")
            self.assertEqual(auth.PENDING_FILE.read_bytes(), before)
            self.handle(self.callback(state=state, id_token="id"))

    def test_closed_stdin_timeout_and_cleanup(self):
        class NoStdin:
            def fileno(self):
                raise ValueError("closed")
        with self.assertRaisesRegex(SystemExit, "timed out"):
            with auth.authorization_attempt(), patch.object(auth.sys, "stdin", NoStdin()):
                auth.wait_for_authentication(timeout=0.02)
        self.assertFalse(auth.PENDING_FILE.exists())
        self.assertFalse(auth.CALLBACK_FILE.exists())
        with auth.authorization_attempt():
            pass  # Lock was released after failure.

    def test_partial_stdin_is_bounded_and_manual_url_works(self):
        read, write = os.pipe()
        self.addCleanup(os.close, write)
        stream = os.fdopen(read, "rb")
        self.addCleanup(stream.close)
        with auth.authorization_attempt() as (state, _), patch.object(auth.sys, "stdin", stream):
            os.write(write, self.callback(state=state, id_token="id").encode() + b"\n")
            self.assertIn("id_token=id", auth.wait_for_authentication(timeout=0.5))
            with self.assertRaisesRegex(SystemExit, "already"):
                self.handle(self.callback(state=state, id_token="other"))
            os.write(write, b"partial-without-newline")
            with self.assertRaisesRegex(SystemExit, "timed out"):
                auth.wait_for_authentication(timeout=0.02)

    def test_failed_and_interrupted_login_preserve_credentials(self):
        auth.write_credentials("existing", {"accountId": "c", "displayName": "Name"})
        before = auth.CREDENTIALS_FILE.read_bytes()
        for failure in (KeyboardInterrupt(), EOFError(), SystemExit("failed")):
            with patch.object(auth, "open_browser", side_effect=failure), self.assertRaises(SystemExit):
                auth.authorize(None)
            self.assertEqual(auth.CREDENTIALS_FILE.read_bytes(), before)
            self.assertFalse(auth.PENDING_FILE.exists())
            self.assertFalse(auth.CALLBACK_FILE.exists())

    def test_http_errors_do_not_echo_secrets(self):
        error = urllib.error.HTTPError("https://test.invalid", 403, "Forbidden", {}, io.BytesIO(b"SECRET_TOKEN"))
        with patch.object(auth.HTTP_OPENER, "open", side_effect=error), self.assertRaises(SystemExit) as caught:
            auth.request_json("https://test.invalid")
        self.assertNotIn("SECRET_TOKEN", str(caught.exception))
        with patch.object(auth.HTTP_OPENER, "open", return_value=io.BytesIO(b"x" * 1048577)), self.assertRaises(SystemExit):
            auth.request_json("https://test.invalid")

    def test_redirects_never_forward_credentials(self):
        calls = []

        class FakeTransport(urllib.request.HTTPSHandler, urllib.request.HTTPHandler):
            def https_open(self, request):
                calls.append(request)
                headers = Message()
                headers["Location"] = "http://evil.invalid/steal"
                response = urllib.response.addinfourl(io.BytesIO(b""), headers, request.full_url, 302)
                response.msg = "Found"
                return response

            http_open = https_open

        opener = urllib.request.build_opener(auth.NoRedirects(), FakeTransport())
        with patch.object(auth, "HTTP_OPENER", opener), self.assertRaisesRegex(SystemExit, "HTTP 302"):
            auth.request_json(auth.ACCOUNTS_ENDPOINT, headers={"Authorization": "Bearer synthetic-secret"})
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0].full_url, auth.ACCOUNTS_ENDPOINT)

    def test_interrupt_after_save_does_not_claim_credentials_unchanged(self):
        original = auth.write_credentials

        def save_then_interrupt(*args):
            original(*args)
            raise KeyboardInterrupt()

        with (
            patch.object(auth.secrets, "token_urlsafe", side_effect=["state", "nonce"]),
            patch.object(auth, "open_browser"),
            patch.object(auth, "wait_for_authentication", return_value=self.callback(state="state", id_token=token())),
            patch.object(auth, "get_game_session", return_value="new-session"),
            patch.object(auth, "get_accounts", return_value=[{"accountId": "c", "displayName": "Name"}]),
            patch.object(auth, "write_credentials", side_effect=save_then_interrupt),
            self.assertRaises(SystemExit) as caught,
        ):
            auth.authorize(None)
        self.assertNotIn("unchanged", str(caught.exception))
        self.assertEqual(auth.read_credentials()["JX_SESSION_ID"], "new-session")
        self.assertFalse(auth.PENDING_FILE.exists())

    def test_manual_input_cannot_override_a_delivered_browser_callback(self):
        read, write = os.pipe()
        self.addCleanup(os.close, write)
        stream = os.fdopen(read, "rb")
        self.addCleanup(stream.close)
        os.write(write, b"stale-invalid-paste\n")
        with auth.authorization_attempt() as (state, _), patch.object(auth.sys, "stdin", stream):
            url = self.callback(state=state, id_token="browser")

            def deliver_between_poll_and_stdin(*args):
                self.handle(url)
                return [read], [], []

            with patch.object(auth.select, "select", side_effect=deliver_between_poll_and_stdin):
                self.assertEqual(auth.wait_for_authentication(timeout=1), url)

    def test_initialization_interruption_cleans_published_state(self):
        original = auth.atomic_write_private

        def publish_then_interrupt(path, contents):
            original(path, contents)
            if path == auth.PENDING_FILE:
                raise KeyboardInterrupt()

        with patch.object(auth, "atomic_write_private", side_effect=publish_then_interrupt), self.assertRaises(KeyboardInterrupt):
            with auth.authorization_attempt():
                self.fail("Initialization should have been interrupted")
        self.assertFalse(auth.PENDING_FILE.exists())
        self.assertFalse(auth.CALLBACK_FILE.exists())
        with auth.authorization_attempt():
            pass

    def test_terminal_echo_disabled_and_restored(self):
        master, slave = os.openpty()
        self.addCleanup(os.close, master)
        stream = os.fdopen(slave, "rb")
        self.addCleanup(stream.close)
        original = termios.tcgetattr(slave)
        original[6][termios.VMIN] = 2
        original[6][termios.VTIME] = 3
        termios.tcsetattr(slave, termios.TCSANOW, original)
        original = termios.tcgetattr(slave)
        for result in ("url", SystemExit("timed out"), KeyboardInterrupt()):
            def wait(_timeout):
                hidden = termios.tcgetattr(slave)
                self.assertFalse(hidden[3] & (termios.ECHO | termios.ECHONL | termios.ICANON))
                self.assertEqual(hidden[6][termios.VMIN], 1)
                self.assertEqual(hidden[6][termios.VTIME], 0)
                if isinstance(result, BaseException):
                    raise result
                return result
            with patch.object(auth.sys, "stdin", stream), patch.object(auth, "_wait_for_authentication", side_effect=wait):
                if isinstance(result, BaseException):
                    with self.assertRaises(type(result)):
                        auth.wait_for_authentication(timeout=1)
                else:
                    self.assertEqual(auth.wait_for_authentication(timeout=1), "url")
            self.assertEqual(termios.tcgetattr(slave), original)

    def test_terminal_discards_unread_input_on_all_exits(self):
        original_wait = auth._wait_for_authentication
        for outcome in ("browser", "timeout", "interrupt", "sigterm"):
            with self.subTest(outcome=outcome):
                master, slave = os.openpty()
                self.addCleanup(os.close, master)
                stream = os.fdopen(slave, "rb")
                self.addCleanup(stream.close)
                with auth.cancellation_signals(), auth.authorization_attempt() as (state, _):
                    url = self.callback(state=state, id_token="browser")
                    if outcome == "browser":
                        self.handle(url)

                    def wait(timeout):
                        self.assertFalse(termios.tcgetattr(slave)[3] & termios.ECHO)
                        os.write(master, b"synthetic unfinished secret")
                        if outcome == "interrupt":
                            raise KeyboardInterrupt()
                        if outcome == "sigterm":
                            os.kill(os.getpid(), signal.SIGTERM)
                        return original_wait(timeout)

                    with patch.object(auth.sys, "stdin", stream), patch.object(auth, "_wait_for_authentication", side_effect=wait):
                        if outcome == "browser":
                            self.assertEqual(auth.wait_for_authentication(timeout=1), url)
                        else:
                            error = KeyboardInterrupt if outcome == "interrupt" else SystemExit
                            with self.assertRaises(error):
                                auth.wait_for_authentication(timeout=0)
                # A shell reading the restored terminal must not inherit the secret.
                os.write(master, b"\n")
                self.assertEqual(os.read(slave, 1024), b"\n")

    def test_terminal_paste_above_canonical_line_limit(self):
        master, slave = os.openpty()
        self.addCleanup(os.close, master)
        stream = os.fdopen(slave, "rb")
        self.addCleanup(stream.close)
        original_wait = auth._wait_for_authentication
        with auth.authorization_attempt() as (state, _):
            url = self.callback(state=state, id_token="a" * 5000)
            self.assertLess(len(url), auth.MAX_CALLBACK)

            def wait(timeout):
                self.assertFalse(termios.tcgetattr(slave)[3] & termios.ECHO)
                os.write(master, url.encode() + b"\n")
                return original_wait(timeout)

            with patch.object(auth.sys, "stdin", stream), patch.object(auth, "_wait_for_authentication", side_effect=wait):
                self.assertEqual(auth.wait_for_authentication(timeout=1), url)

    def test_callback_contention_is_bounded(self):
        auth.ensure_data_dir()
        with auth.file_lock(auth.CALLBACK_LOCK), patch.object(auth.time, "monotonic", side_effect=[0, 6]):
            with self.assertRaisesRegex(SystemExit, "busy"):
                with auth.callback_guard():
                    self.fail("Contended lock was acquired")

    def test_sigterm_cleans_attempt_and_restores_handler(self):
        previous = signal.getsignal(signal.SIGTERM)
        with self.assertRaises(SystemExit) as caught:
            with auth.cancellation_signals(), auth.authorization_attempt():
                os.kill(os.getpid(), signal.SIGTERM)
        self.assertEqual(caught.exception.code, 143)
        self.assertEqual(signal.getsignal(signal.SIGTERM), previous)
        self.assertFalse(auth.PENDING_FILE.exists())
        with auth.authorization_attempt():
            pass

    def test_simultaneous_callbacks_only_deliver_once(self):
        env = {**os.environ, "HOME": self.temporary.name, "XDG_DATA_HOME": self.temporary.name,
               "PYTHONPATH": str(Path(auth.__file__).parent.parent)}
        with auth.authorization_attempt() as (state, _):
            url = self.callback(state=state, id_token="id")
            children = [subprocess.Popen(
                [sys.executable, "-m", "jagex_auth", "handle-url", url],
                env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            ) for _ in range(2)]
            try:
                results = [child.communicate(timeout=10) for child in children]
                self.assertEqual(sorted(child.returncode for child in children), [0, 1], results)
                self.assertEqual(auth.wait_for_authentication(timeout=1), url)
            finally:
                for child in children:
                    if child.poll() is None:
                        child.kill()
                        child.communicate(timeout=10)

    def test_cross_process_callbacks_and_stale_recovery(self):
        env = {**os.environ, "HOME": self.temporary.name, "XDG_DATA_HOME": self.temporary.name,
               "PYTHONPATH": str(Path(auth.__file__).parent.parent)}
        with auth.authorization_attempt() as (state, _):
            result = subprocess.run([sys.executable, "-m", "jagex_auth", "handle-url", self.callback(state=state, id_token="id")], env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("id_token=id", auth.wait_for_authentication(timeout=1))
        # Simulate abrupt termination: kernel releases locks but files may remain.
        child = subprocess.Popen([sys.executable, "-c", "import jagex_auth as a,time; c=a.authorization_attempt(); c.__enter__(); print('ready',flush=True); time.sleep(30)"], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.assertEqual(child.stdout.readline().strip(), "ready")
            child.kill()
            child.wait(timeout=10)
            self.assertTrue(auth.PENDING_FILE.exists())
            with self.assertRaisesRegex(SystemExit, "No active"):
                self.handle(self.callback(state="stale", id_token="id"))
            with auth.authorization_attempt():
                pass
            self.assertFalse(auth.PENDING_FILE.exists())
        finally:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=10)
            child.stdout.close()
            child.stderr.close()


if __name__ == "__main__":
    unittest.main()

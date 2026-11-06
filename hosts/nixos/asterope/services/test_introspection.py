import importlib.util
import io
import json
import os
import pathlib
import time
import unittest
import urllib.error
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location(
    "introspection", pathlib.Path(__file__).with_name("introspection.py")
)
introspection = importlib.util.module_from_spec(spec)
with (
    patch.dict(os.environ, {"CREDENTIALS_DIRECTORY": "/test-credentials"}),
    patch.object(pathlib.Path, "read_text", return_value="test-only-secret"),
):
    spec.loader.exec_module(introspection)


class IntrospectionTests(unittest.TestCase):
    def setUp(self):
        self.claims = {
            "active": True,
            "client_id": "stalwart",
            "iss": "https://auth.m7.rs/application/o/stalwart/",
            "aud": "stalwart",
            "exp": time.time() + 300,
            "scope": "openid email profile offline_access",
            "mail_account": "contato@lumis.cards",
        }

    def handler(self, body=b"token=header.payload.signature", path="/introspect"):
        handler = introspection.Handler.__new__(introspection.Handler)
        handler.path = path
        handler.headers = {"Content-Length": str(len(body))}
        handler.rfile = io.BytesIO(body)
        handler.wfile = io.BytesIO()
        handler.send_response = Mock()
        handler.send_header = Mock()
        handler.end_headers = Mock()
        handler.send_error = Mock()
        return handler

    def test_valid_token(self):
        self.assertTrue(introspection.valid_claims(self.claims))
        self.assertTrue(introspection.valid_claims(self.claims | {"aud": ["stalwart"]}))

    def test_invalid_claims(self):
        for changes in (
            {"active": False},
            {"active": "true"},
            {"client_id": "grafana"},
            {"iss": "https://untrusted.invalid/"},
            {"aud": "grafana"},
            {"exp": time.time() - 1},
            {"exp": "99999999999"},
            {"scope": "openid profile"},
            {"scope": ["email"]},
            {"mail_account": "contato@m7.rs"},
            {"mail_account": "@lumis.cards"},
            {"mail_account": " contato@lumis.cards"},
            {"mail_account": "contato@lumis.cards\n"},
        ):
            with self.subTest(changes=changes):
                self.assertFalse(introspection.valid_claims(self.claims | changes))
        for claims in (None, [], {}, {"active": False}):
            self.assertFalse(introspection.valid_claims(claims))

    def test_valid_introspection(self):
        handler = self.handler()
        response = io.BytesIO(json.dumps(self.claims).encode())
        with patch.object(
            introspection.urllib.request, "urlopen", return_value=response
        ) as request:
            handler.do_POST()
        request.assert_called_once()
        handler.send_error.assert_not_called()
        self.assertEqual(json.loads(handler.wfile.getvalue()), self.claims)

    def test_invalid_claims_get_authentication_rejection(self):
        for changes in (
            {"active": False},
            {"scope": "openid profile"},
            {"client_id": "other-client"},
            {"exp": time.time() - 1},
        ):
            with self.subTest(changes=changes):
                handler = self.handler()
                response = io.BytesIO(json.dumps(self.claims | changes).encode())
                with patch.object(
                    introspection.urllib.request, "urlopen", return_value=response
                ):
                    handler.do_POST()
                handler.send_response.assert_called_once_with(401)
                self.assertEqual(
                    json.loads(handler.wfile.getvalue()), {"active": False}
                )

    def test_refresh_token_rejected_without_contacting_provider(self):
        handler = self.handler(b"token=opaque-refresh-token")
        with patch.object(introspection.urllib.request, "urlopen") as request:
            handler.do_POST()
        request.assert_not_called()
        handler.send_response.assert_called_once_with(401)
        self.assertEqual(json.loads(handler.wfile.getvalue()), {"active": False})

    def test_provider_unavailable_fails_closed(self):
        handler = self.handler()
        with patch.object(
            introspection.urllib.request,
            "urlopen",
            side_effect=urllib.error.URLError("unavailable"),
        ):
            handler.do_POST()
        handler.send_error.assert_called_once_with(
            503, "Identity provider unavailable or invalid response"
        )
        self.assertEqual(handler.wfile.getvalue(), b"")

    def test_malformed_response_fails_closed(self):
        handler = self.handler()
        with patch.object(
            introspection.urllib.request,
            "urlopen",
            return_value=io.BytesIO(b"bad json"),
        ):
            handler.do_POST()
        self.assertEqual(handler.send_error.call_args.args[0], 503)

    def test_bad_requests(self):
        for body, path, status in (
            (b"", "/introspect", 400),
            (b"token=", "/introspect", 400),
            (b"x" * 16385, "/introspect", 400),
            (b"token=x", "/wrong", 404),
        ):
            with self.subTest(status=status, length=len(body)):
                handler = self.handler(body, path)
                handler.do_POST()
                self.assertEqual(handler.send_error.call_args.args[0], status)


if __name__ == "__main__":
    unittest.main()

"""Require an active, mail-scoped Gablogin token before passing claims to Stalwart."""

import base64
import json
import os
import pathlib
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CLIENT_ID = "stalwart-resource"
MAIL_CLIENT_ID = "stalwart"
ENDPOINT = "https://auth.m7.rs/application/o/introspect/"
SECRET = (
    pathlib.Path(os.environ["CREDENTIALS_DIRECTORY"], "client-secret")
    .read_text()
    .strip()
)
AUTH = base64.b64encode(f"{CLIENT_ID}:{SECRET}".encode()).decode()


def valid_claims(claims):
    if not isinstance(claims, dict):
        return False
    account = claims.get("mail_account")
    expiry = claims.get("exp")
    scope = claims.get("scope")
    audience = claims.get("aud")
    return (
        claims.get("active") is True
        and claims.get("client_id") == MAIL_CLIENT_ID
        and claims.get("iss") == "https://auth.m7.rs/application/o/stalwart/"
        and (
            audience == MAIL_CLIENT_ID
            or isinstance(audience, list)
            and MAIL_CLIENT_ID in audience
        )
        and type(expiry) in (int, float)
        and expiry > time.time()
        and isinstance(scope, str)
        and "email" in scope.split()
        and isinstance(account, str)
        and re.fullmatch(r"[a-z0-9][a-z0-9._+%-]*@lumis\.cards", account) is not None
    )


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def respond(self, claims, status=200):
        data = json.dumps(claims).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def reject(self):
        # A 200 without identity makes Stalwart report a transient backend fault.
        self.respond({"active": False}, status=401)

    def do_POST(self):
        if self.path != "/introspect":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 16384:
                self.send_error(400)
                return
            params = urllib.parse.parse_qs(self.rfile.read(length).decode())
            token = params.get("token", [""])[0]
            if not token:
                self.send_error(400)
                return
            # Authentik also introspects opaque refresh tokens; never accept those.
            if token.count(".") != 2:
                self.reject()
                return
            request = urllib.request.Request(
                ENDPOINT,
                data=urllib.parse.urlencode(
                    {"token": token, "token_type_hint": "access_token"}
                ).encode(),
                headers={"Authorization": f"Basic {AUTH}"},
            )
            with urllib.request.urlopen(request, timeout=10) as response:
                claims = json.load(response)
            if not valid_claims(claims):
                self.reject()
                return
            self.respond(claims)
        except (ValueError, TypeError, OSError, urllib.error.URLError):
            self.send_error(503, "Identity provider unavailable or invalid response")


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8081), Handler).serve_forever()

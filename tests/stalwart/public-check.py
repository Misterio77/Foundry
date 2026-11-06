#!/usr/bin/env python3
"""Public, non-delivering checks; optionally authenticate with a private token file."""

import argparse
import base64
import http.client
import imaplib
import ipaddress
import json
import shlex
import smtplib
import socket
import ssl
import stat
import sys
import urllib.parse
import urllib.request
from pathlib import Path

HOST = "mail.lumis.cards"
ISSUER = "https://auth.m7.rs/application/o/stalwart/"
ADDRESSES = ["155.138.245.163", "2001:19f0:6401:cf2::1"]
TLS = ssl.create_default_context()
TIMEOUT = 15


class HTTPSOnAddress(http.client.HTTPSConnection):
    def __init__(self, address):
        super().__init__(HOST, context=TLS, timeout=TIMEOUT)
        self.address = address

    def connect(self):
        self.sock = TLS.wrap_socket(
            socket.create_connection((self.address, 443), TIMEOUT), server_hostname=HOST
        )


class IMAPOnAddress(imaplib.IMAP4_SSL):
    def __init__(self, address):
        self.address = address
        super().__init__(HOST, 993, ssl_context=TLS, timeout=TIMEOUT)

    def _create_socket(self, timeout):
        return TLS.wrap_socket(
            socket.create_connection((self.address, self.port), timeout),
            server_hostname=HOST,
        )


def http(address, method, path, headers=None, body=None):
    connection = HTTPSOnAddress(address)
    try:
        connection.request(method, path, body=body, headers=headers or {})
        response = connection.getresponse()
        return (
            response.status,
            {k.lower(): v for k, v in response.getheaders()},
            response.read(),
        )
    finally:
        connection.close()


def smtp(address, port):
    client = smtplib.SMTP(timeout=TIMEOUT, local_hostname="validation.lumis.cards")
    client._host = HOST
    raw = socket.create_connection((address, port), TIMEOUT)
    client.sock = TLS.wrap_socket(raw, server_hostname=HOST) if port == 465 else raw
    try:
        assert client.getreply()[0] == 220
        assert client.ehlo()[0] == 250
        if port == 25:
            assert client.has_extn("starttls") and not client.has_extn("auth")
            client.starttls(context=TLS)
            client.ehlo()
        return client
    except BaseException:
        client.close()
        raise


def dns(record_type, name="lumis.cards"):
    url = "https://dns.google/resolve?" + urllib.parse.urlencode(
        {"name": name, "type": record_type}
    )
    with urllib.request.urlopen(url, timeout=TIMEOUT) as response:
        result = json.load(response)
    assert result["Status"] == 0
    return [answer["data"] for answer in result.get("Answer", [])]


def load_token(path):
    if not path:
        return None
    metadata = path.stat()
    if not stat.S_ISREG(metadata.st_mode) or stat.S_IMODE(metadata.st_mode) & 0o077:
        raise ValueError("Token file must be private")
    text = path.read_text().strip()
    token = json.loads(text)["access_token"] if text.startswith("{") else text
    if not isinstance(token, str) or not token or any(ch.isspace() for ch in token):
        raise ValueError("Invalid token file")
    return token


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--token-file",
        type=Path,
        help="0600 raw access token or JSON with access_token",
    )
    parser.add_argument("--account", default="contato@lumis.cards")
    parser.add_argument(
        "--message-id",
        help="Optional existing synthetic fixture; searches only, never fetches mail",
    )
    args = parser.parse_args()
    if not __debug__:
        parser.error("Do not disable assertions with python -O")
    try:
        token = load_token(args.token_file)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(json.dumps({"error": type(error).__name__}), file=sys.stderr)
        return 1
    checks = []

    def check(name, action):
        try:
            action()
            checks.append({"name": name, "ok": True})
        except Exception as error:  # noqa: BLE001
            # Do not include exception messages: SASL/HTTP errors may contain credentials.
            checks.append({"name": name, "ok": False, "error": type(error).__name__})

    def mx():
        assert dns("MX") == ["1 mail.lumis.cards."]

    def spf():
        assert any(
            "v=spf1" in value
            and "ip4:" + ADDRESSES[0] in value
            and "ip6:" + ADDRESSES[1] in value
            for value in dns("TXT")
        )

    def signing_records():
        for selector, algorithm in (("202611r", "rsa"), ("202611e", "ed25519")):
            values = [
                "".join(shlex.split(value))
                for value in dns("TXT", selector + "._domainkey.lumis.cards")
            ]
            key = next(value for value in values if "k=" + algorithm in value)
            fields = dict(
                part.strip().split("=", 1) for part in key.split(";") if "=" in part
            )
            decoded = base64.b64decode(fields["p"], validate=True)
            assert len(decoded) == 32 if algorithm == "ed25519" else len(decoded) >= 256
        assert any("v=DMARC1" in value for value in dns("TXT", "_dmarc.lumis.cards"))

    def forward_reverse():
        for address, kind in zip(ADDRESSES, ("A", "AAAA")):
            assert ipaddress.ip_address(address) in [
                ipaddress.ip_address(value) for value in dns(kind, HOST)
            ]
            assert HOST + "." in dns(
                "PTR", ipaddress.ip_address(address).reverse_pointer
            )

    def issuer_discovery():
        with urllib.request.urlopen(
            ISSUER + ".well-known/openid-configuration", timeout=TIMEOUT
        ) as response:
            value = json.load(response)
        assert value["issuer"] == ISSUER
        assert "S256" in value["code_challenge_methods_supported"]
        assert {"authorization_code", "refresh_token"} <= set(
            value["grant_types_supported"]
        )

    check("public MX", mx)
    check("SPF permits both public addresses", spf)
    check("RSA/Ed25519 DKIM and DMARC records", signing_records)
    check("public A/AAAA and matching PTR", forward_reverse)
    check("Gablogin issuer, PKCE and grant metadata", issuer_discovery)

    for address in ADDRESSES:

        def ingress(address=address):
            with smtp(address, 25) as client:
                assert not client.has_extn("auth")
                assert client.mail("")[0] == 250
                assert client.rcpt("contato@lumis.cards")[0] == 250
                assert client.rcpt("validation-no-delivery@lumis.cards")[0] == 250
                assert client.rcpt("recipient@example.net")[0] == 550
                client.rset()

        def submission(address=address):
            with smtp(address, 465) as client:
                mechanisms = client.esmtp_features.get("auth", "").split()
                assert (
                    "XOAUTH2" in mechanisms
                    and "PLAIN" not in mechanisms
                    and "LOGIN" not in mechanisms
                )

        def imap(address=address):
            with IMAPOnAddress(address) as client:
                assert "AUTH=XOAUTH2" in client.capabilities
                assert "AUTH=OAUTHBEARER" in client.capabilities

        def metadata(address=address):
            status, _, body = http(
                address, "GET", "/.well-known/oauth-protected-resource"
            )
            result = json.loads(body)
            assert status == 200 and result["authorization_servers"] == [ISSUER]
            assert result["resource"] == "https://" + HOST

        def api_acl(address=address):
            assert http(address, "GET", "/api/principal")[0] == 403
            assert (
                http(
                    address, "GET", "/api/principal", {"X-Forwarded-For": "100.77.0.1"}
                )[0]
                == 403
            )

        def bearer_challenge(address=address):
            status, headers, _ = http(address, "PROPFIND", "/dav/cal", {"Depth": "0"})
            assert status == 401
            assert 'Bearer resource_metadata="https://' + HOST in headers.get(
                "www-authenticate", ""
            )

        for name, action in [
            ("SMTP STARTTLS, recipients, no open relay", ingress),
            ("submission TLS and OAuth mechanisms", submission),
            ("IMAP TLS and OAuth mechanisms", imap),
            ("OAuth resource metadata", metadata),
            ("management ACL and spoof rejection", api_acl),
            ("DAV bearer challenge", bearer_challenge),
        ]:
            check(f"{address}: {name}", action)

        if token:

            def jmap(address=address):
                status, _, body = http(
                    address,
                    "GET",
                    "/.well-known/jmap",
                    {"Authorization": "Bearer " + token},
                )
                assert status == 200 and json.loads(body)["username"] == args.account

            def smtp_auth(address=address):
                with smtp(address, 465) as client:
                    payload = f"user={args.account}\x01auth=Bearer {token}\x01\x01"
                    assert (
                        client.auth(
                            "XOAUTH2",
                            lambda challenge=None: payload if challenge is None else "",
                        )[0]
                        == 235
                    )

            def imap_auth(address=address):
                for mechanism in ("XOAUTH2", "OAUTHBEARER"):
                    payload = (
                        f"user={args.account}\x01auth=Bearer {token}\x01\x01"
                        if mechanism == "XOAUTH2"
                        else f"n,a={args.account},\x01auth=Bearer {token}\x01\x01"
                    )
                    with IMAPOnAddress(address) as client:
                        assert (
                            client.authenticate(
                                mechanism,
                                lambda challenge, payload=payload: (
                                    payload.encode() if not challenge else b""
                                ),
                            )[0]
                            == "OK"
                        )
                        assert client.select("INBOX", readonly=True)[0] == "OK"
                        if args.message_id:
                            status, result = client.uid(
                                "SEARCH",
                                None,
                                "HEADER",
                                "Message-ID",
                                json.dumps(args.message_id),
                            )
                            assert status == "OK" and any(result)

            def dav(address=address):
                for path in ("/dav/cal", "/dav/card"):
                    status, _, _ = http(
                        address,
                        "PROPFIND",
                        path,
                        {"Authorization": "Bearer " + token, "Depth": "0"},
                    )
                    assert status == 207

            for name, action in [
                ("bearer JMAP identity", jmap),
                ("bearer SMTP XOAUTH2", smtp_auth),
                ("IMAP XOAUTH2/OAUTHBEARER and read-only INBOX", imap_auth),
                ("bearer DAV", dav),
            ]:
                check(f"{address}: {name}", action)

    print(
        json.dumps(
            {
                "checks": checks,
                "token_supplied": bool(token),
                "limits": [
                    "No mail delivered or DAV data changed",
                    "Does not perform browser login, refresh or revocation",
                    "Actual owner clients are not tested by this script",
                ],
            },
            indent=2,
        )
    )
    return 0 if all(result["ok"] for result in checks) else 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Probe a one-off Asterope snapshot without opening the live RocksDB twice."""

import argparse
import base64
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import tomllib
import urllib.parse
import urllib.request
from pathlib import Path

EMAIL_FIELDS = [
    "email-from",
    "email-to",
    "email-cc",
    "email-bcc",
    "email-subject",
    "email-body",
    "email-attachment",
    "email-received-at",
    "email-sent-at",
    "email-size",
    "email-has-attachment",
    "email-headers",
]


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs)


def probe(args):
    if os.readlink("/proc/self/ns/net") == os.readlink("/proc/1/ns/net"):
        raise RuntimeError("Refusing to probe outside a private network namespace")
    password = Path("/run/secrets/stalwart-admin-password").read_text().strip()
    authorization = "Basic " + base64.b64encode(f"admin:{password}".encode()).decode()

    def api(path, payload=None):
        request = urllib.request.Request(
            "http://127.0.0.1:8080" + path,
            data=json.dumps(payload).encode() if payload is not None else None,
            headers={
                "Authorization": authorization,
                "Content-Type": "application/json",
            },
        )
        with urllib.request.urlopen(request, timeout=20) as response:
            result = json.load(response)
        if (
            "error" in result
            or "data" not in result
            and "methodResponses" not in result
        ):
            raise RuntimeError("API envelope rejected")
        return result

    def jmap(method, params):
        result = api(
            "/jmap/",
            {
                "using": [
                    "urn:ietf:params:jmap:core",
                    "urn:ietf:params:jmap:mail",
                    "urn:ietf:params:jmap:sieve",
                ],
                "methodCalls": [
                    [method, {"accountId": args.account_id, **params}, "probe"]
                ],
            },
        )["methodResponses"][0]
        if result[0] != method:
            raise RuntimeError("JMAP method rejected")
        return result[1]

    def query(header_value):
        return jmap(
            "Email/query", {"filter": {"header": ["Message-ID", header_value]}}
        )["ids"]

    for attempt in range(60):
        try:
            api("/api/principal/" + urllib.parse.quote(args.account, safe=""))
            break
        except (OSError, ValueError):
            if attempt == 59:
                raise
            time.sleep(0.5)

    if args.probe == "index" and not args.fields_configured:
        api(
            "/api/settings",
            [
                {"type": "clear", "prefix": "storage.search-index.email.fields"},
                {
                    "type": "insert",
                    "prefix": "storage.search-index.email.fields",
                    "values": [[str(i), field] for i, field in enumerate(EMAIL_FIELDS)],
                    "assert_empty": False,
                },
            ],
        )
        api("/api/reload")
    if args.probe == "index":
        api("/api/store/reindex/email/" + urllib.parse.quote(args.account, safe=""))
        for _ in range(60):
            if query(args.message_id):
                break
            time.sleep(0.5)
        return {
            "header_after_explicit_fields": bool(query(args.message_id)),
            "header_with_angles": bool(query("<" + args.message_id + ">")),
            "header_substring": bool(query(args.message_id.split("@", 1)[0])),
        }

    principal = api("/api/principal/" + urllib.parse.quote(args.account, safe=""))[
        "data"
    ]
    catchall = api("/api/principal/lumis-catchall")["data"]
    scripts = jmap("SieveScript/get", {"properties": ["name", "isActive"]})["list"]
    ids = jmap("Email/query", {"limit": 200})["ids"]
    emails = jmap("Email/get", {"ids": ids, "properties": ["id", "messageId"]})["list"]
    matches = [
        email["id"] for email in emails if args.message_id in email.get("messageId", [])
    ]
    if not matches:
        raise RuntimeError("Synthetic fixture not found in snapshot")
    body = jmap(
        "Email/get",
        {
            "ids": matches,
            "properties": ["id", "bodyValues", "textBody"],
            "fetchTextBodyValues": True,
        },
    )["list"]
    return {
        "contact_principal_restored": args.account in principal["emails"],
        "catchall_restored": catchall["externalMembers"] == ["hi@m7.rs"],
        "active_forwarding_restored": any(
            script["name"] == "lumis-forwarding" and script["isActive"]
            for script in scripts
        ),
        "synthetic_body_restored": any(
            value.get("value")
            for email in body
            for value in email.get("bodyValues", {}).values()
        ),
        "header_before_explicit_fields": bool(query(args.message_id)),
    }


def restore(args):
    if os.geteuid() != 0:
        raise RuntimeError("Run as root on Asterope; this script never invokes sudo")
    unit_text = Path(
        run(
            "systemctl", "show", "stalwart", "-p", "FragmentPath", "--value"
        ).stdout.strip()
    ).read_text()
    binary = re.search(r"^ExecStart=(\S+)", unit_text, re.MULTILINE).group(1)
    original_config = Path(re.search(r"--config=([^\s\";]+)", unit_text).group(1))
    if not re.search(r"\b0\.15\.5\b", run(binary, "--version").stdout):
        raise RuntimeError("This helper supports only Stalwart 0.15.5")
    parsed_config = tomllib.loads(original_config.read_text())
    configured_fields = (
        parsed_config.get("storage", {})
        .get("search-index", {})
        .get("email", {})
        .get("fields", [])
    )
    credentials = [
        line for line in unit_text.splitlines() if line.startswith("LoadCredential=")
    ]
    if not credentials:
        raise RuntimeError("Expected native NixOS credential wiring")
    base = Path(tempfile.mkdtemp(prefix=".stalwart-restore-", dir="/persist"))
    snapshot = base / "snapshot"
    restored = base / "state"
    fixture_unit = "stalwart-restore-" + base.name.rsplit("-", 1)[-1] + ".service"
    started = False
    snapshot_created = False
    success = False
    try:
        run("btrfs", "subvolume", "snapshot", "-r", "/persist", str(snapshot))
        snapshot_created = True
        shutil.copytree(snapshot / "var/lib/stalwart", restored, symlinks=True)
        config = base / "config.toml"
        config.write_text(
            original_config.read_text().replace(
                "/run/credentials/stalwart.service/",
                f"/run/credentials/{fixture_unit}/",
            )
        )
        config.chmod(0o444)
        command = [
            "systemd-run",
            "--quiet",
            "--unit=" + fixture_unit,
            "--property=Type=exec",
            "--property=PrivateNetwork=yes",
            "--property=PrivateTmp=yes",
            "--property=PrivateDevices=yes",
            "--property=PrivateIPC=yes",
            "--property=NoNewPrivileges=yes",
            "--property=ProtectSystem=strict",
            "--property=ProtectHome=yes",
            "--property=ReadWritePaths=/var/lib/stalwart",
            "--property=MemoryMax=256M",
            "--property=CPUQuota=25%",
            "--property=Nice=10",
            f"--property=BindPaths={restored}:/var/lib/stalwart",
            f"--property=BindReadOnlyPaths={config}:/run/stalwart-restore.toml",
        ]
        for credential in credentials:
            command.append("--property=" + credential)
        command += [binary, "--config=/run/stalwart-restore.toml"]
        run(*command)
        started = True
        pid = int(
            run("systemctl", "show", fixture_unit, "-p", "MainPID", "--value").stdout
        )
        if pid <= 0 or os.readlink(f"/proc/{pid}/ns/net") == os.readlink(
            "/proc/1/ns/net"
        ):
            raise RuntimeError("Fixture network isolation not established")
        if not os.path.samefile(
            restored / "db", f"/proc/{pid}/root/var/lib/stalwart/db"
        ):
            raise RuntimeError("Fixture is not using its own database copy")
        results = {"private_network_verified": True, "private_database_verified": True}
        for phase in ("baseline", "index"):
            output = run(
                "nsenter",
                "--target",
                str(pid),
                "--net",
                sys.executable,
                str(Path(__file__).resolve()),
                "--probe",
                phase,
                "--account",
                args.account,
                "--account-id",
                args.account_id,
                "--message-id",
                args.message_id,
                *(
                    ["--fields-configured"]
                    if set(configured_fields) == set(EMAIL_FIELDS)
                    else []
                ),
            ).stdout
            results.update(json.loads(output))
        required = [
            "contact_principal_restored",
            "catchall_restored",
            "active_forwarding_restored",
            "synthetic_body_restored",
            "header_after_explicit_fields",
        ]
        if not all(results[key] for key in required):
            raise RuntimeError("A restore or indexing assertion failed")
        success = True
        if args.keep_snapshot:
            results["snapshot"] = str(snapshot)
        return results
    finally:
        if started:
            run("systemctl", "stop", fixture_unit)
            subprocess.run(
                ["systemctl", "reset-failed", fixture_unit],
                check=False,
                capture_output=True,
            )
        shutil.rmtree(restored, ignore_errors=True)
        (base / "config.toml").unlink(missing_ok=True)
        if snapshot_created and not (success and args.keep_snapshot):
            run("btrfs", "subvolume", "delete", str(snapshot))
        if not (success and args.keep_snapshot):
            base.rmdir()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--account", default="contato@lumis.cards")
    parser.add_argument("--account-id", default="c")
    parser.add_argument(
        "--message-id",
        required=True,
        help="Existing synthetic message, without angle brackets",
    )
    parser.add_argument(
        "--keep-snapshot",
        action="store_true",
        help="Keep the read-only source for encrypted export",
    )
    parser.add_argument(
        "--probe", choices=["baseline", "index"], help=argparse.SUPPRESS
    )
    parser.add_argument(
        "--fields-configured", action="store_true", help=argparse.SUPPRESS
    )
    args = parser.parse_args()
    if not __debug__:
        parser.error("Do not disable assertions with python -O")
    if not re.fullmatch(r"lumis-mx-[a-z0-9-]+@lumis\.cards", args.message_id):
        parser.error("Only the synthetic cutover fixture is supported")
    try:
        print(json.dumps(probe(args) if args.probe else restore(args), sort_keys=True))
    except Exception as error:  # noqa: BLE001
        # Provider responses, credentials and message contents must not reach logs.
        failure = {"error": type(error).__name__}
        if type(error) is RuntimeError:
            failure["detail"] = str(error)
        if isinstance(error, subprocess.CalledProcessError):
            failure.update(command=Path(error.cmd[0]).name, returncode=error.returncode)
            try:
                failure["child"] = json.loads(error.stderr)
            except ValueError:
                pass
        if isinstance(error, urllib.error.HTTPError):
            failure["http_status"] = error.code
        print(json.dumps(failure), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

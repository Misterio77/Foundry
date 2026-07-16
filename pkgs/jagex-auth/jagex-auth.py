# Note: partially vibecoded (pi running gpt 5.5)
#
# Uses same mechanism as bolt (sans the GUI and CEF parts), so should be safe to use.
# But might potentially break ToS, so please use at your own risk.
import argparse
import base64
import hashlib
import json
import os
import secrets
import select
import socket
import stat
import subprocess
import sys
import time
import urllib.parse
import webbrowser

import requests
from pathlib import Path

CLIENT_ID = "com_jagex_auth_desktop_launcher"
CONSENT_CLIENT_ID = "1fddee4e-b100-4f4e-b2b0-097f9088f9d2"
ORIGIN = "https://account.jagex.com"
REDIRECT_URI = "https://secure.runescape.com/m=weblogin/launcher-redirect"
CONSENT_REDIRECT_URI = "http://localhost"
SCOPE = "openid offline gamesso.token.create user.profile.read"
CONSENT_SCOPE = "openid offline"
SESSION_ENDPOINT = "https://auth.jagex.com/game-session/v1/sessions"
ACCOUNTS_ENDPOINT = "https://auth.jagex.com/game-session/v1/accounts"
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"

DATA_DIR = (
    Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "jagex-auth"
)
TOKEN_FILE = DATA_DIR / "tokens.json"
LAUNCHER_CALLBACK_FILE = DATA_DIR / "launcher-callback-url"

HTTP = requests.Session()
HTTP.headers.update(
    {
        "Accept": "application/json",
        "Accept-Language": "en-US,en;q=0.9",
        "User-Agent": USER_AGENT,
    }
)


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode().rstrip("=")


def make_verifier() -> str:
    return b64url(secrets.token_bytes(72))


def make_challenge(verifier: str) -> str:
    return b64url(hashlib.sha256(verifier.encode()).digest())


def ensure_data_dir() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    DATA_DIR.chmod(0o700)


def load_tokens() -> dict:
    if not TOKEN_FILE.exists():
        raise SystemExit("No stored tokens. Run: jagex-auth authorize")
    return json.loads(TOKEN_FILE.read_text())


def store_tokens(tokens: dict) -> None:
    ensure_data_dir()
    now = int(time.time())
    old = json.loads(TOKEN_FILE.read_text()) if TOKEN_FILE.exists() else {}

    for key in (
        "refresh_token",
        "consent_id_token",
        "session_id",
        "character_id",
        "display_name",
    ):
        if not tokens.get(key) and old.get(key):
            tokens[key] = old[key]

    tokens["obtained_at"] = now
    tokens["expires_at"] = now + int(tokens.get("expires_in", 0))

    tmp = TOKEN_FILE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(tokens, indent=2, sort_keys=True) + "\n")
    tmp.chmod(stat.S_IRUSR | stat.S_IWUSR)
    tmp.replace(TOKEN_FILE)


def response_json(response: requests.Response) -> dict | list:
    try:
        response.raise_for_status()
        return response.json()
    except requests.HTTPError as err:
        detail = response.text
        if "cf-error-details" in detail or "cloudflare" in detail.lower():
            detail = "Cloudflare denied the request"
        elif len(detail) > 1000:
            detail = detail[:1000] + "..."
        raise SystemExit(
            f"HTTP {response.status_code} from {response.url}: {detail}"
        ) from err


def request_json(
    url: str,
    *,
    form: dict | None = None,
    body: dict | None = None,
    headers: dict | None = None,
) -> dict | list:
    try:
        return response_json(HTTP.post(url, data=form, json=body, headers=headers))
    except requests.RequestException as err:
        raise SystemExit(f"Request failed for {url}: {err}") from err


def get_json(url: str, *, headers: dict | None = None) -> dict | list:
    try:
        return response_json(HTTP.get(url, headers=headers))
    except requests.RequestException as err:
        raise SystemExit(f"Request failed for {url}: {err}") from err


def open_browser(url: str) -> None:
    if not webbrowser.open(url):
        print(f"Open this URL manually:\n{url}", file=sys.stderr)


def get_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def query_param(url: str, name: str) -> str | None:
    parsed = urllib.parse.urlparse(url.strip())
    if parsed.scheme == "jagex":
        params = {}
        for part in parsed.path.split(","):
            key, sep, value = part.partition("=")
            if sep:
                params[key] = urllib.parse.unquote_plus(value)
        return params.get(name)

    params = urllib.parse.parse_qs(parsed.query)
    if name not in params and parsed.fragment:
        params = urllib.parse.parse_qs(parsed.fragment)
    values = params.get(name)
    return values[0] if values else None


def make_launcher_auth_url(verifier: str, state: str) -> str:
    params = {
        "auth_method": "",
        "login_type": "",
        "flow": "launcher",
        "response_type": "code",
        "client_id": CLIENT_ID,
        "redirect_uri": REDIRECT_URI,
        "code_challenge": make_challenge(verifier),
        "code_challenge_method": "S256",
        "prompt": "login",
        "scope": SCOPE,
        "state": state,
    }
    return f"{ORIGIN}/oauth2/auth?{urllib.parse.urlencode(params)}"


def exchange_launcher_callback(
    callback: str,
    verifier: str,
    expected_state: str,
) -> dict:
    code = query_param(callback, "code")
    returned_state = query_param(callback, "state")
    if not code:
        raise SystemExit("Could not find code= in callback URL")
    if returned_state != expected_state:
        raise SystemExit("OAuth state mismatch")

    return request_json(
        f"{ORIGIN}/oauth2/token",
        form={
            "grant_type": "authorization_code",
            "client_id": CLIENT_ID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": REDIRECT_URI,
        },
    )


def make_consent_url(
    id_token_hint: str,
    nonce: str,
    state: str,
) -> str:
    consent_params = {
        "id_token_hint": id_token_hint,
        "nonce": nonce,
        "prompt": "consent",
        "redirect_uri": CONSENT_REDIRECT_URI,
        "response_type": "id_token code",
        "state": state,
        "client_id": CONSENT_CLIENT_ID,
        "scope": CONSENT_SCOPE,
    }
    return f"{ORIGIN}/oauth2/auth?{urllib.parse.urlencode(consent_params)}"


def exchange_consent_code(code: str) -> str:
    response = request_json(
        f"{ORIGIN}/oauth2/token",
        form={
            "grant_type": "authorization_code",
            "client_id": CONSENT_CLIENT_ID,
            "code": code,
            "redirect_uri": CONSENT_REDIRECT_URI,
        },
    )
    id_token_value = response.get("id_token")
    if not id_token_value:
        raise SystemExit("Consent token exchange did not return id_token")
    return id_token_value


def finish_authorize(
    tokens: dict,
    consent_callback: str,
    nonce: str,
    consent_state: str,
) -> None:
    consent_id_token = query_param(consent_callback, "id_token")
    consent_code = query_param(consent_callback, "code")
    returned_consent_state = query_param(consent_callback, "state")
    if returned_consent_state != consent_state:
        raise SystemExit("OAuth consent state mismatch")
    if not consent_id_token:
        if not consent_code:
            raise SystemExit(
                "Could not find id_token= or code= in consent callback URL"
            )
        consent_id_token = exchange_consent_code(consent_code)

    consent_payload = decode_jwt_payload(consent_id_token)
    if consent_payload.get("nonce") != nonce:
        raise SystemExit("OAuth consent nonce mismatch")

    tokens["consent_id_token"] = consent_id_token
    tokens["session_id"] = get_session_id(consent_id_token)
    configure_character(tokens, interactive=True)
    store_tokens(tokens)
    write_game_credentials(tokens)
    print(f"Stored Jagex OAuth tokens in {TOKEN_FILE}", file=sys.stderr)


def run_authorization(
    open_launcher,
    open_consent,
    wait_consent_callback,
    after_launcher_callback=lambda: None,
) -> None:
    verifier = make_verifier()
    state = secrets.token_urlsafe(32)
    if LAUNCHER_CALLBACK_FILE.exists():
        LAUNCHER_CALLBACK_FILE.unlink()

    open_launcher(make_launcher_auth_url(verifier, state))
    callback = wait_for_launcher_callback(state)
    after_launcher_callback()
    tokens = exchange_launcher_callback(callback, verifier, state)

    nonce = secrets.token_urlsafe(32)
    consent_state = secrets.token_urlsafe(32)
    open_consent(make_consent_url(tokens["id_token"], nonce, consent_state))
    finish_authorize(
        tokens,
        wait_consent_callback(consent_state),
        nonce,
        consent_state,
    )


def authorize(_args: argparse.Namespace) -> None:
    print("Opening Jagex login in your browser.", file=sys.stderr)
    print(
        "After login, click 'Return to launcher' or paste the callback URL.",
        file=sys.stderr,
    )
    print(f"It should start with: {REDIRECT_URI}?code=...", file=sys.stderr)
    print("The jagex:code=... URL is also accepted.", file=sys.stderr)

    def open_consent(url: str) -> None:
        print("\nOpening Jagex consent step in your browser.", file=sys.stderr)
        print(
            "After consent, copy the localhost callback URL. "
            "Paste still works as fallback.",
            file=sys.stderr,
        )
        print("It should start with: http://localhost", file=sys.stderr)
        open_browser(url)

    run_authorization(open_browser, open_consent, wait_for_consent_callback)


def is_consent_callback_url(url: str, expected_state: str) -> bool:
    return (
        url.startswith(("http://localhost#", "http://localhost/#"))
        and query_param(url, "state") == expected_state
        and (has_param(url, "id_token") or has_param(url, "code"))
    )


def has_param(url: str, name: str) -> bool:
    return query_param(url, name) is not None


def is_launcher_callback(url: str, expected_state: str) -> bool:
    return query_param(url, "state") == expected_state and has_param(url, "code")


def read_clipboard() -> str | None:
    try:
        result = subprocess.run(
            ["wl-paste", "--no-newline"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=0.5,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def wait_for_callback(
    prompt: str,
    predicate,
    callback_file: Path | None = None,
) -> str:
    seen_clipboard = read_clipboard()
    print(f"\n{prompt}: ", end="", flush=True)
    while True:
        if callback_file and callback_file.exists():
            callback = callback_file.read_text().strip()
            callback_file.unlink()
            print("received via jagex: handler", file=sys.stderr)
            return callback

        clipboard = read_clipboard()
        if clipboard and clipboard != seen_clipboard and predicate(clipboard):
            print("received via clipboard", file=sys.stderr)
            return clipboard

        readable, _, _ = select.select([sys.stdin], [], [], 0.25)
        if readable:
            return sys.stdin.readline().strip()


def wait_for_launcher_callback(expected_state: str) -> str:
    return wait_for_callback(
        "Launcher callback URL",
        lambda url: is_launcher_callback(url, expected_state),
        LAUNCHER_CALLBACK_FILE,
    )


def wait_for_consent_callback(expected_state: str) -> str:
    return wait_for_callback(
        "Consent callback URL",
        lambda url: is_consent_callback_url(url, expected_state),
    )


def handle_url(args: argparse.Namespace) -> None:
    ensure_data_dir()
    LAUNCHER_CALLBACK_FILE.write_text(args.url + "\n")
    LAUNCHER_CALLBACK_FILE.chmod(stat.S_IRUSR | stat.S_IWUSR)


def refresh(_args: argparse.Namespace | None = None) -> None:
    tokens = load_tokens()
    refresh_token = tokens.get("refresh_token")
    if not refresh_token:
        raise SystemExit("No refresh token stored. Run: jagex-auth authorize")

    new_tokens = request_json(
        f"{ORIGIN}/oauth2/token",
        form={
            "grant_type": "refresh_token",
            "client_id": CLIENT_ID,
            "refresh_token": refresh_token,
        },
    )
    store_tokens(new_tokens)


def refresh_if_needed() -> dict:
    tokens = load_tokens()
    if int(tokens.get("expires_at", 0)) - int(time.time()) < 60:
        refresh()
        tokens = load_tokens()
    return tokens


def get_session_id(id_token_value: str) -> str:
    response = request_json(
        SESSION_ENDPOINT,
        body={"idToken": id_token_value},
    )
    return response["sessionId"]


def get_accounts(session_id: str) -> list[dict]:
    accounts = get_json(
        ACCOUNTS_ENDPOINT,
        headers={"Authorization": f"Bearer {session_id}"},
    )
    return accounts if isinstance(accounts, list) else []


def choose_account(accounts: list[dict]) -> dict | None:
    if not accounts:
        return None
    if len(accounts) == 1:
        return accounts[0]

    print("\nAvailable RuneScape characters:", file=sys.stderr)
    for index, account in enumerate(accounts, start=1):
        name = account.get("displayName") or "<unnamed>"
        print(f"  {index}. {name} ({account.get('accountId')})", file=sys.stderr)

    while True:
        choice = input("Character number: ").strip()
        if choice.isdigit() and 1 <= int(choice) <= len(accounts):
            return accounts[int(choice) - 1]
        print("Invalid character number", file=sys.stderr)


def configure_character(tokens: dict, *, interactive: bool) -> None:
    if tokens.get("character_id") and tokens.get("display_name"):
        return
    if not tokens.get("session_id"):
        return

    accounts = get_accounts(tokens["session_id"])
    account = (
        choose_account(accounts) if interactive else (accounts[0] if accounts else None)
    )
    if account:
        tokens["character_id"] = account.get("accountId")
        tokens["display_name"] = account.get("displayName")


def java_property_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace(" ", "\\ ").replace("\n", "\\n")


def write_game_credentials(tokens: dict) -> None:
    ensure_data_dir()

    values = {
        "JX_SESSION_ID": tokens.get("session_id"),
        "JX_CHARACTER_ID": tokens.get("character_id"),
        "JX_DISPLAY_NAME": tokens.get("display_name"),
    }
    path = DATA_DIR / "credentials.properties"
    lines = [
        f"{key}={java_property_escape(value)}" for key, value in values.items() if value
    ]
    path.write_text("\n".join(lines) + "\n")
    path.chmod(stat.S_IRUSR | stat.S_IWUSR)
    print(f"Wrote game credentials to {path}", file=sys.stderr)


def session(_args: argparse.Namespace) -> None:
    tokens = refresh_if_needed()
    if not tokens.get("session_id"):
        if not tokens.get("consent_id_token"):
            raise SystemExit("No consent ID token stored. Run: jagex-auth authorize")
        tokens["session_id"] = get_session_id(tokens["consent_id_token"])
        configure_character(tokens, interactive=False)
        store_tokens(tokens)

    write_game_credentials(tokens)
    print(tokens["session_id"])


def decode_jwt_payload(token: str) -> dict:
    payload = token.split(".")[1]
    padded = payload + "=" * ((4 - len(payload) % 4) % 4)
    return json.loads(base64.urlsafe_b64decode(padded))


def maybe_decode_jwt(token: str | None) -> dict | None:
    return decode_jwt_payload(token) if token else None


def show(_args: argparse.Namespace) -> None:
    tokens = load_tokens()
    safe = {
        k: tokens.get(k)
        for k in (
            "token_type",
            "scope",
            "expires_in",
            "obtained_at",
            "expires_at",
        )
    }
    safe.update(
        {
            "id_payload": maybe_decode_jwt(tokens.get("id_token")),
            "consent_id_payload": maybe_decode_jwt(tokens.get("consent_id_token")),
            "has_session_id": bool(tokens.get("session_id")),
        }
    )
    print(json.dumps(safe, indent=2, sort_keys=True))


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="jagex-auth",
        description="Jagex launcher OAuth helper",
    )
    sub = parser.add_subparsers(
        required=True,
        metavar="{authorize,session,show}",
    )

    commands = (
        "authorize",
        "session",
        "show",
    )
    for name in commands:
        cmd = sub.add_parser(name)
        cmd.set_defaults(func=globals()[name.replace("-", "_")])

    handle = sub.add_parser("handle-url")
    handle.add_argument("url")
    handle.set_defaults(func=handle_url)
    sub._choices_actions = [
        action for action in sub._choices_actions if action.dest != "handle-url"
    ]

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

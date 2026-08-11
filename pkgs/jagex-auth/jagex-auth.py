import argparse
import base64
import json
import os
import secrets
import stat
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from pathlib import Path

AUTH_ENDPOINT = "https://account.jagex.com/oauth2/auth"
CLIENT_ID = "com_jagex_auth_desktop_launcher_rs_hub"
REDIRECT_URI = "https://account.jagex.com/en-GB/launcher/successful-login"
SESSION_ENDPOINT = "https://auth.runescape.com/game-session/v1/sessions"
ACCOUNTS_ENDPOINT = "https://auth.runescape.com/game-session/v2/accounts"

DATA_DIR = (
    Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "jagex-auth"
)
CALLBACK_FILE = DATA_DIR / "auth-callback-url"
CREDENTIALS_FILE = DATA_DIR / "credentials.properties"


def ensure_data_dir() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    DATA_DIR.chmod(0o700)


def request_json(
    url: str,
    *,
    method: str = "GET",
    body: dict | None = None,
    headers: dict[str, str] | None = None,
) -> dict | list:
    request_headers = {"Accept": "application/json", **(headers or {})}
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        request_headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        url,
        data=data,
        headers=request_headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            result = json.load(response)
    except urllib.error.HTTPError as err:
        detail = err.read().decode(errors="replace")
        if "cloudflare" in detail.lower():
            detail = "Cloudflare denied the request"
        elif len(detail) > 1000:
            detail = detail[:1000] + "..."
        raise SystemExit(f"HTTP {err.code} from {url}: {detail}") from err
    except (urllib.error.URLError, TimeoutError) as err:
        raise SystemExit(f"Request failed for {url}: {err}") from err
    except json.JSONDecodeError as err:
        raise SystemExit(f"Invalid JSON from {url}") from err
    if not isinstance(result, (dict, list)):
        raise SystemExit(f"Invalid JSON from {url}")
    return result


def make_auth_url(state: str, nonce: str) -> str:
    params = {
        "redirect_uri": REDIRECT_URI,
        "response_type": "id_token",
        "client_id": CLIENT_ID,
        "scope": "openid",
        "state": state,
        "nonce": nonce,
    }
    return f"{AUTH_ENDPOINT}?{urllib.parse.urlencode(params)}"


def open_browser(url: str) -> None:
    if not webbrowser.open(url):
        print(f"Open this URL manually:\n{url}", file=sys.stderr)


def callback_params(url: str) -> dict[str, str]:
    parsed = urllib.parse.urlparse(url.strip())
    if (
        parsed.scheme != "rshub"
        or parsed.netloc != "auth"
        or parsed.path != "/callback"
    ):
        raise SystemExit("Invalid Jagex authentication callback URL")
    return {
        key: values[0]
        for key, values in urllib.parse.parse_qs(parsed.fragment).items()
        if values
    }


def wait_for_callback() -> str:
    print("Waiting for the browser callback...", file=sys.stderr)
    while True:
        try:
            callback = CALLBACK_FILE.read_text().strip()
        except FileNotFoundError:
            time.sleep(0.1)
            continue
        CALLBACK_FILE.unlink(missing_ok=True)
        return callback


def decode_jwt_payload(token: str) -> dict:
    try:
        payload = token.split(".")[1]
        padded = payload + "=" * (-len(payload) % 4)
        decoded = json.loads(base64.urlsafe_b64decode(padded))
    except (IndexError, ValueError, json.JSONDecodeError) as err:
        raise SystemExit("Jagex returned an invalid ID token") from err
    if not isinstance(decoded, dict):
        raise SystemExit("Jagex returned an invalid ID token payload")
    return decoded


def get_game_session(id_token: str) -> str:
    result = request_json(
        SESSION_ENDPOINT,
        method="POST",
        body={"idToken": id_token},
    )
    session_id = result.get("sessionId") if isinstance(result, dict) else None
    if not session_id:
        raise SystemExit("Jagex did not return a game session ID")
    return session_id


def get_accounts(session_id: str) -> list[dict]:
    result = request_json(
        ACCOUNTS_ENDPOINT,
        headers={"Authorization": f"Bearer {session_id}"},
    )
    if not isinstance(result, list) or not result:
        raise SystemExit("No RuneScape characters found")
    return result


def choose_account(accounts: list[dict]) -> dict:
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


def java_property_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace(" ", "\\ ").replace("\n", "\\n")


def write_credentials(session_id: str, account: dict) -> None:
    character_id = account.get("accountId")
    display_name = account.get("displayName")
    if not character_id or not display_name:
        raise SystemExit("Selected character is missing an ID or display name")

    ensure_data_dir()
    values = {
        "JX_SESSION_ID": session_id,
        "JX_CHARACTER_ID": character_id,
        "JX_DISPLAY_NAME": display_name,
    }
    contents = "".join(
        f"{key}={java_property_escape(value)}\n" for key, value in values.items()
    )
    temporary = CREDENTIALS_FILE.with_suffix(".properties.tmp")
    temporary.write_text(contents)
    temporary.chmod(stat.S_IRUSR | stat.S_IWUSR)
    temporary.replace(CREDENTIALS_FILE)


def authorize(_args: argparse.Namespace) -> None:
    ensure_data_dir()
    CALLBACK_FILE.unlink(missing_ok=True)
    state = secrets.token_urlsafe(32)
    nonce = secrets.token_urlsafe(32)

    print("Opening Jagex login in your browser.", file=sys.stderr)
    open_browser(make_auth_url(state, nonce))

    params = callback_params(wait_for_callback())
    if params.get("state") != state:
        raise SystemExit("OAuth state mismatch")
    id_token = params.get("id_token")
    if not id_token:
        raise SystemExit("Jagex callback did not contain an ID token")

    payload = decode_jwt_payload(id_token)
    if payload.get("nonce") != nonce:
        raise SystemExit("OAuth nonce mismatch")
    if not payload.get("sub") or not payload.get("nickname"):
        raise SystemExit("Jagex ID token is missing account information")

    session_id = get_game_session(id_token)
    account = choose_account(get_accounts(session_id))
    write_credentials(session_id, account)
    print(
        f"Authenticated {payload['nickname']} as {account['displayName']}.",
        file=sys.stderr,
    )


def handle_url(args: argparse.Namespace) -> None:
    callback_params(args.url)
    ensure_data_dir()
    temporary = CALLBACK_FILE.with_suffix(".tmp")
    temporary.write_text(args.url + "\n")
    temporary.chmod(stat.S_IRUSR | stat.S_IWUSR)
    temporary.replace(CALLBACK_FILE)


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="jagex-auth",
        description="Authenticate RuneScape clients with a Jagex account",
    )
    commands = parser.add_subparsers(required=True)

    authorize_parser = commands.add_parser("authorize", help="authenticate with Jagex")
    authorize_parser.set_defaults(func=authorize)

    callback_parser = commands.add_parser(
        "handle-url", help="receive the browser authentication callback"
    )
    callback_parser.add_argument("url")
    callback_parser.set_defaults(func=handle_url)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

import argparse
import base64
import json
import os
import secrets
import select
import stat
import sys
import tempfile
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
CREDENTIALS_FILE = DATA_DIR / "credentials.json"
CREDENTIAL_KEYS = ("JX_SESSION_ID", "JX_CHARACTER_ID", "JX_DISPLAY_NAME")


def ensure_data_dir() -> None:
    DATA_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    if DATA_DIR.is_symlink() or not DATA_DIR.is_dir():
        raise SystemExit("Refusing unsafe jagex-auth data directory")
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
        # Authentication error responses can contain secrets. Never echo bodies.
        raise SystemExit(f"HTTP {err.code} from {url}") from err
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


def is_handler_callback(url: str) -> bool:
    parsed = urllib.parse.urlparse(url)
    return (
        parsed.scheme == "rshub"
        and parsed.netloc == "auth"
        and parsed.path == "/callback"
    )


def authentication_params(value: str, expected_state: str) -> dict[str, str]:
    value = value.strip()
    if value.count(".") == 2 and "://" not in value:
        return {"id_token": value}

    parsed = urllib.parse.urlparse(value)
    is_success_page = (
        parsed.scheme == "https"
        and parsed.netloc == "account.jagex.com"
        and parsed.path.endswith("/launcher/successful-login")
    )
    if not is_handler_callback(value) and not is_success_page:
        raise SystemExit("Invalid Jagex authentication response")
    params = {
        key: values[0]
        for key, values in urllib.parse.parse_qs(parsed.fragment).items()
        if values
    }
    if params.get("state") != expected_state:
        raise SystemExit("OAuth state mismatch")
    return params


def wait_for_authentication() -> str:
    print(
        "Waiting for the browser callback. You can also paste the successful-login "
        "URL or ID token:",
        file=sys.stderr,
    )
    watch_stdin = True
    while True:
        try:
            callback = CALLBACK_FILE.read_text().strip()
        except FileNotFoundError:
            pass
        else:
            CALLBACK_FILE.unlink(missing_ok=True)
            return callback

        if watch_stdin:
            readable, _, _ = select.select([sys.stdin], [], [], 0.1)
            if readable:
                line = sys.stdin.readline()
                if line:
                    return line.strip()
                watch_stdin = False
        else:
            time.sleep(0.1)


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


def validate_credentials(value: object) -> dict[str, str]:
    if (
        not isinstance(value, dict)
        or type(value.get("version")) is not int
        or value["version"] != 1
        or set(value) != {"version", *CREDENTIAL_KEYS}
        or any(
            not isinstance(value[key], str) or not value[key] or "\0" in value[key]
            for key in CREDENTIAL_KEYS
        )
    ):
        raise ValueError("Invalid credential schema")
    return {key: value[key] for key in CREDENTIAL_KEYS}


def atomic_write_private(path: Path, contents: str) -> None:
    # mkstemp creates the file with 0600, even under a permissive umask.
    fd, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(contents)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def write_credentials(session_id: str, account: dict) -> None:
    values = {
        "version": 1,
        "JX_SESSION_ID": session_id,
        "JX_CHARACTER_ID": account.get("accountId"),
        "JX_DISPLAY_NAME": account.get("displayName"),
    }
    try:
        validate_credentials(values)
    except ValueError:
        raise SystemExit("Invalid session or selected character information") from None
    ensure_data_dir()
    try:
        atomic_write_private(CREDENTIALS_FILE, json.dumps(values, ensure_ascii=False) + "\n")
    except OSError:
        raise SystemExit("Could not save credentials; existing credentials were not replaced") from None


def read_credentials() -> dict[str, str]:
    try:
        ensure_data_dir()
        fd = os.open(CREDENTIALS_FILE, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, "r", encoding="utf-8") as stream:
            info = os.fstat(stream.fileno())
            if (
                not stat.S_ISREG(info.st_mode)
                or info.st_uid != os.getuid()
                or stat.S_IMODE(info.st_mode) & 0o077
                or info.st_size > 65536
            ):
                raise ValueError("Unsafe credential file")
            contents = stream.read(65537)
            if len(contents) > 65536:
                raise ValueError("Credential file too large")
            return validate_credentials(json.loads(contents))
    except FileNotFoundError:
        message = "No saved credentials"
    except (OSError, ValueError):
        message = "Invalid or unsafe saved credentials"
    raise SystemExit(f"{message}; run 'jagex-auth authorize'.")


def launch(args: argparse.Namespace) -> None:
    command = args.command
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        raise SystemExit("Usage: jagex-auth launch -- COMMAND [ARG ...]")
    environment = {**os.environ, **read_credentials()}
    try:
        os.execvpe(command[0], command, environment)
    except FileNotFoundError:
        print("Client executable not found", file=sys.stderr)
        raise SystemExit(127) from None
    except OSError:
        print("Could not execute client", file=sys.stderr)
        raise SystemExit(126) from None


def authorize(_args: argparse.Namespace) -> None:
    ensure_data_dir()
    CALLBACK_FILE.unlink(missing_ok=True)
    state = secrets.token_urlsafe(32)
    nonce = secrets.token_urlsafe(32)

    print("Opening Jagex login in your browser.", file=sys.stderr)
    open_browser(make_auth_url(state, nonce))

    params = authentication_params(wait_for_authentication(), state)
    id_token = params.get("id_token")
    if not id_token:
        raise SystemExit("Jagex authentication response did not contain an ID token")

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
    if not is_handler_callback(args.url):
        raise SystemExit("Invalid Jagex authentication callback URL")
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

    launch_parser = commands.add_parser(
        "launch", help="launch a client using saved credentials (noninteractive)"
    )
    launch_parser.add_argument("command", nargs=argparse.REMAINDER)
    launch_parser.set_defaults(func=launch)

    args = parser.parse_args()
    args.func(args)


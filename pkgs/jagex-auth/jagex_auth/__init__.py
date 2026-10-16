import argparse
import base64
from contextlib import contextmanager
import fcntl
import json
import os
import re
import secrets
import select
import signal
import stat
import sys
import tempfile
import termios
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
ISSUER = "https://account.jagex.com/"
AUTH_TIMEOUT = 300
MAX_CALLBACK = 16384

DATA_DIR = (
    Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "jagex-auth"
)
CALLBACK_FILE = DATA_DIR / "auth-callback.json"
PENDING_FILE = DATA_DIR / "pending.json"
AUTH_LOCK = DATA_DIR / "authorize.lock"
CALLBACK_LOCK = DATA_DIR / "callback.lock"
CREDENTIALS_FILE = DATA_DIR / "credentials.json"
CREDENTIAL_KEYS = ("JX_SESSION_ID", "JX_CHARACTER_ID", "JX_DISPLAY_NAME")


def ensure_data_dir() -> None:
    DATA_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    if DATA_DIR.is_symlink() or not DATA_DIR.is_dir():
        raise SystemExit("Refusing unsafe jagex-auth data directory")
    DATA_DIR.chmod(0o700)


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Fixed authentication endpoints must not redirect tokens or credentials.
        return None


HTTP_OPENER = urllib.request.build_opener(NoRedirects())


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
        with HTTP_OPENER.open(request, timeout=30) as response:
            raw = response.read(1048577)
            if len(raw) > 1048576:
                raise SystemExit("Authentication server response too large")
            result = json.loads(raw)
    except urllib.error.HTTPError as err:
        # Authentication error responses can contain secrets. Never echo bodies.
        err.close()
        raise SystemExit(f"HTTP {err.code} from {url}") from None
    except (urllib.error.URLError, TimeoutError):
        raise SystemExit(f"Request failed for {url}") from None
    except (ValueError, UnicodeError) as err:
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


def response_url(value: str, *, handler_only: bool = False) -> urllib.parse.ParseResult:
    if not isinstance(value, str) or len(value) > MAX_CALLBACK or any(ord(c) < 32 for c in value):
        raise SystemExit("Invalid Jagex authentication response")
    try:
        parsed = urllib.parse.urlparse(value)
    except ValueError:
        raise SystemExit("Invalid Jagex authentication response") from None
    origin = parsed._replace(fragment="").geturl()
    allowed = {"rshub://auth/callback"}
    if not handler_only:
        allowed.add(REDIRECT_URI)
    if origin not in allowed:
        raise SystemExit("Invalid Jagex authentication response URL")
    return parsed


def authentication_params(value: str, expected_state: str) -> dict[str, str]:
    parsed = response_url(value)
    try:
        pairs = urllib.parse.parse_qsl(
            parsed.fragment, keep_blank_values=True, strict_parsing=True,
            max_num_fields=16, errors="strict",
        )
    except (ValueError, UnicodeError):
        raise SystemExit("Invalid authentication response parameters") from None
    params = dict(pairs)
    if len(params) != len(pairs):
        raise SystemExit("Duplicate authentication response parameters")
    if not expected_state or not secrets.compare_digest(
        params.get("state", "").encode("utf-8"), expected_state.encode("utf-8")
    ):
        raise SystemExit("OAuth state mismatch")
    if "error" in params:
        raise SystemExit("Jagex declined authentication; please try again")
    if not params.get("id_token"):
        raise SystemExit("Jagex authentication response did not contain an ID token")
    return params


@contextmanager
def file_lock(path: Path):
    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise SystemExit("Unsafe authorization lock file")
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            yield
        finally:
            fcntl.flock(fd, fcntl.LOCK_UN)
    finally:
        os.close(fd)


@contextmanager
def callback_guard():
    # Short critical section; bounded retry avoids hanging on a wedged handler.
    deadline = time.monotonic() + 5
    while True:
        lock = file_lock(CALLBACK_LOCK)
        try:
            lock.__enter__()
            break
        except BlockingIOError:
            if time.monotonic() >= deadline:
                raise SystemExit("Authentication callback busy; please retry") from None
            time.sleep(0.01)
    try:
        yield
    finally:
        lock.__exit__(None, None, None)


@contextmanager
def private_terminal_input():
    try:
        fd = sys.stdin.fileno()
    except (AttributeError, ValueError, OSError):
        fd = None
    if fd is None or not os.isatty(fd):
        yield
        return
    original = termios.tcgetattr(fd)
    hidden = original.copy()
    # Read long pastes ourselves instead of the terminal's bounded line buffer.
    hidden[3] &= ~(termios.ECHO | termios.ECHONL | termios.ICANON)
    hidden[6] = original[6].copy()
    hidden[6][termios.VMIN] = 1
    hidden[6][termios.VTIME] = 0
    try:
        termios.tcsetattr(fd, termios.TCSANOW, hidden)
        yield
    finally:
        # Never hand an unfinished secret paste back to the shell.
        termios.tcsetattr(fd, termios.TCSAFLUSH, original)


def wait_for_authentication(timeout: float = AUTH_TIMEOUT) -> str:
    with private_terminal_input():
        return _wait_for_authentication(timeout)


def consume_browser_callback() -> str | None:
    # Caller holds callback_guard. A delivered browser response wins over stdin.
    try:
        callback = read_private_json(CALLBACK_FILE, MAX_CALLBACK * 2)
    except FileNotFoundError:
        return None
    if not isinstance(callback, dict) or not isinstance(callback.get("url"), str):
        raise SystemExit("Invalid browser callback file")
    close_callback_delivery()
    CALLBACK_FILE.unlink()
    return callback["url"]


def _wait_for_authentication(timeout: float) -> str:
    print("Waiting for browser callback; you can also paste the successful-login URL (input hidden):", file=sys.stderr)
    deadline = time.monotonic() + timeout
    buffer = b""
    try:
        stdin = sys.stdin.fileno()
    except (AttributeError, ValueError, OSError):
        stdin = None
    while time.monotonic() < deadline:
        with callback_guard():
            callback = consume_browser_callback()
            if callback is not None:
                return callback
        if stdin is None:
            time.sleep(0.1)
            continue
        readable, _, _ = select.select([stdin], [], [], 0.1)
        if readable:
            chunk = os.read(stdin, MAX_CALLBACK + 1)
            buffer += chunk
            with callback_guard():
                callback = consume_browser_callback()
                if callback is not None:
                    return callback
                if len(buffer) > MAX_CALLBACK:
                    raise SystemExit("Authentication response too large")
                if b"\n" in buffer or (not chunk and buffer):
                    try:
                        url = buffer.split(b"\n", 1)[0].rstrip(b"\r").decode("utf-8")
                    except UnicodeError:
                        raise SystemExit("Invalid authentication response encoding") from None
                    pending = read_private_json(PENDING_FILE)
                    if not isinstance(pending, dict) or pending.get("accepting") is not True:
                        raise SystemExit("Authentication response already consumed")
                    close_callback_delivery()
                    return url
            if not chunk:
                stdin = None
    raise SystemExit("Authentication timed out; run 'jagex-auth authorize' again")


def close_callback_delivery() -> None:
    # Caller holds callback_guard; terminal and browser delivery share this flag.
    pending = read_private_json(PENDING_FILE)
    if not isinstance(pending, dict):
        raise SystemExit("Invalid pending authorization")
    pending["accepting"] = False
    atomic_write_private(PENDING_FILE, json.dumps(pending))


def decode_id_token(token: str, nonce: str) -> dict:
    """Check unverified claims for consistency, NOT authenticity.

    Only Jagex's successful session exchange and character listing establish
    authentication. Do not use these decoded claims to authorize anything.
    """
    try:
        if not isinstance(token, str) or len(token) > MAX_CALLBACK:
            raise ValueError("Token too large or invalid")
        parts = token.split(".")
        if len(parts) != 3 or any(not re.fullmatch(r"[A-Za-z0-9_-]+", p) for p in parts):
            raise ValueError("Invalid JWT encoding")
        decoded = [base64.b64decode(p + "=" * (-len(p) % 4), altchars=b"-_", validate=True) for p in parts]
        header, payload = (json.loads(part) for part in decoded[:2])
        if not isinstance(header, dict) or not isinstance(payload, dict):
            raise ValueError("Invalid JWT objects")
        if payload.get("iss") != ISSUER:
            raise ValueError("Unexpected issuer")
        audience = payload.get("aud")
        if audience != CLIENT_ID and not (
            isinstance(audience, list) and audience
            and all(isinstance(value, str) for value in audience) and CLIENT_ID in audience
        ):
            raise ValueError("Unexpected audience")
        if any(type(payload.get(claim)) is not int for claim in ("iat", "exp")):
            raise ValueError("Invalid token timestamps")
        now = time.time()
        if payload["exp"] <= now - 30 or payload["iat"] > now + 30:
            raise ValueError("Token expired or issued in the future")
        if "nbf" in payload and (type(payload["nbf"]) is not int or payload["nbf"] > now + 30):
            raise ValueError("Invalid token not-before timestamp")
        if not isinstance(payload.get("nonce"), str) or not secrets.compare_digest(
            payload["nonce"].encode("utf-8"), nonce.encode("utf-8")
        ):
            raise SystemExit("OAuth nonce mismatch")
        if payload.get("azp", CLIENT_ID) != CLIENT_ID:
            raise ValueError("Wrong authorized party")
        if isinstance(audience, list) and len(audience) > 1 and payload.get("azp") != CLIENT_ID:
            raise ValueError("Missing authorized party")
        if not all(isinstance(payload.get(k), str) and payload[k] for k in ("sub", "nickname")):
            raise ValueError("Missing account information")
        return payload
    except (ValueError, TypeError, KeyError, OverflowError, RecursionError):
        raise SystemExit("Malformed or inconsistent Jagex ID token (not signature-verified locally)") from None


def get_game_session(id_token: str) -> str:
    result = request_json(
        SESSION_ENDPOINT,
        method="POST",
        body={"idToken": id_token},
    )
    session_id = result.get("sessionId") if isinstance(result, dict) else None
    if not isinstance(session_id, str) or not session_id or any(ord(c) < 32 for c in session_id):
        raise SystemExit("Jagex did not return a game session ID")
    return session_id


def get_accounts(session_id: str) -> list[dict]:
    result = request_json(
        ACCOUNTS_ENDPOINT,
        headers={"Authorization": f"Bearer {session_id}"},
    )
    if not isinstance(result, list) or not result:
        raise SystemExit("No RuneScape characters found")
    if any(
        not isinstance(account, dict)
        or not isinstance(account.get("accountId"), str)
        or not account["accountId"]
        or any(ord(c) < 32 for c in account["accountId"])
        or (account.get("displayName") is not None and (
            not isinstance(account["displayName"], str)
            or any(ord(c) < 32 for c in account["displayName"])
        ))
        for account in result
    ):
        raise SystemExit("Invalid RuneScape character information")
    named = [account for account in result if account.get("displayName")]
    if not named:
        raise SystemExit("No named RuneScape characters found; set a character name and authorize again")
    if len(named) != len(result):
        print("Skipping characters without a display name.", file=sys.stderr)
    return named


def choose_account(accounts: list[dict]) -> dict:
    if len(accounts) == 1:
        return accounts[0]

    print("\nAvailable RuneScape characters:", file=sys.stderr)
    for index, account in enumerate(accounts, start=1):
        name = account.get("displayName") or "<unnamed>"
        print(f"  {index}. {name} ({account.get('accountId')})", file=sys.stderr)

    while True:
        try:
            choice = int(input("Character number: "))
            if 1 <= choice <= len(accounts):
                return accounts[choice - 1]
        except ValueError:
            pass
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


def read_private_json(path: Path, limit: int = 65536):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "r", encoding="utf-8") as stream:
        info = os.fstat(stream.fileno())
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_mode & 0o077
            or info.st_size > limit
        ):
            raise ValueError("Unsafe or oversized private file")
        contents = stream.read(limit + 1)
        if len(contents) > limit:
            raise ValueError("Private file too large")
        return json.loads(contents)


def read_credentials() -> dict[str, str]:
    try:
        ensure_data_dir()
        return validate_credentials(read_private_json(CREDENTIALS_FILE))
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


@contextmanager
def authorization_attempt():
    ensure_data_dir()
    lock = file_lock(AUTH_LOCK)
    try:
        lock.__enter__()
    except BlockingIOError:
        raise SystemExit("Another authorization is already running") from None
    try:
        try:
            state, nonce = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
            with callback_guard():
                CALLBACK_FILE.unlink(missing_ok=True)
                atomic_write_private(PENDING_FILE, json.dumps({
                    "state": state, "expires": time.time() + AUTH_TIMEOUT, "accepting": True,
                }))
            yield state, nonce
        finally:
            with callback_guard():
                PENDING_FILE.unlink(missing_ok=True)
                CALLBACK_FILE.unlink(missing_ok=True)
    finally:
        # Do not unlink lock files: waiters must keep locking the same inode.
        lock.__exit__(None, None, None)


@contextmanager
def cancellation_signals():
    def terminate(signum, _frame):
        raise SystemExit(128 + signum)

    previous = signal.signal(signal.SIGTERM, terminate)
    try:
        yield
    finally:
        signal.signal(signal.SIGTERM, previous)


def authorize(_args: argparse.Namespace) -> None:
    try:
        with cancellation_signals(), authorization_attempt() as (state, nonce):
            print("Opening Jagex login in your browser.", file=sys.stderr)
            open_browser(make_auth_url(state, nonce))
            params = authentication_params(wait_for_authentication(), state)
            payload = decode_id_token(params["id_token"], nonce)
            session_id = get_game_session(params["id_token"])
            account = choose_account(get_accounts(session_id))
            write_credentials(session_id, account)
            print(f"Authenticated {payload['nickname']} as {account['displayName']}.", file=sys.stderr)
    except (KeyboardInterrupt, EOFError):
        raise SystemExit("Authorization cancelled; credentials may already have been saved") from None
    except (OSError, ValueError):
        raise SystemExit("Could not access authorization state safely; please retry") from None


def handle_url(args: argparse.Namespace) -> None:
    response_url(args.url, handler_only=True)
    try:
        ensure_data_dir()
        with callback_guard():
            # A stale pending file is not evidence of a live authorizer.
            try:
                with file_lock(AUTH_LOCK):
                    raise SystemExit("No active authorization; run 'jagex-auth authorize'")
            except BlockingIOError:
                pass
            try:
                pending = read_private_json(PENDING_FILE)
            except FileNotFoundError:
                raise SystemExit("No active authorization") from None
            if (
                not isinstance(pending, dict)
                or not isinstance(pending.get("state"), str)
                or not pending["state"]
                or type(pending.get("expires")) not in (int, float)
                or not time.time() < pending["expires"] <= time.time() + AUTH_TIMEOUT + 1
            ):
                raise SystemExit("Authorization expired or invalid; please retry")
            authentication_params(args.url, pending["state"])
            if pending.get("accepting") is not True or CALLBACK_FILE.exists():
                raise SystemExit("An authentication response has already been delivered")
            atomic_write_private(CALLBACK_FILE, json.dumps({"url": args.url}))
            close_callback_delivery()
    except (OSError, ValueError):
        raise SystemExit("Could not access authorization state safely; please retry") from None


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


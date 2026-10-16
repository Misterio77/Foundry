# Authentication security model

This is an unofficial client for Jagex's existing desktop-launcher authentication
flow, not a separately registered OAuth application. User-operated browser
callback, character selection, and in-game login with RuneLite, HDOS, and RS3
were verified on 2026-10-16. Do not include tokens, callback URLs, credential
files, or HTTP response bodies in reports.

## Protocol and authoritative validation

The following public provider metadata was checked on 2026-10-16:

- Discovery: <https://account.jagex.com/.well-known/openid-configuration>
- Issuer: `https://account.jagex.com/` (including the trailing slash)
- Authorization endpoint: `https://account.jagex.com/oauth2/auth`
- JWKS: <https://account.jagex.com/.well-known/jwks.json>
- Advertised ID-token signing algorithm: `RS256`
- `id_token` is among the advertised response types.

The helper is stdlib-only and does **not verify ID-token signatures locally**,
fetch JWKS, or implement cryptography. The metadata above describes the provider,
not a promise of local cryptographic verification. Token-supplied `jku`/`x5u`
URLs are ignored. HTTP redirects are disabled for authentication requests; HTTPS
certificate verification uses Python's configured trust store.

`authorize` requests an ID token for
`com_jagex_auth_desktop_launcher_rs_hub`, with a fresh unpredictable state and
nonce. The browser response must be a state-bound URL, either exactly
`rshub://auth/callback` or the configured HTTPS successful-login URL, with the
response in the fragment. Query parameters and alternate paths/origins are
rejected. Raw-token paste is intentionally unsupported: it discards the URL's
state binding. Duplicate parameters, provider errors, missing tokens, oversized
inputs, and malformed input are rejected without echoing secrets. Manual terminal input
has echo disabled while waiting and bypasses the terminal's bounded line buffer.
Unread terminal input is discarded when restoring settings on completion,
timeout, or cancellation, so unfinished secret pastes cannot pass back to the
shell. A browser response already delivered wins over concurrent terminal input.

Before exchange, the helper strictly decodes the token and checks unverified
claims for consistency: issuer, audience, integer expiration/issued-at/optional
not-before timestamps (30-second clock skew allowance), nonce, nonempty
subject/nickname, and authorized party (`azp`) if present or required for multiple
audiences. These are input sanity checks and request binding, **not proof of
identity**. A forged token with matching claims can pass them; neither its
header nor decoded account information establishes a login.

The authentication authority is Jagex's fixed HTTPS game-session endpoint:
`https://auth.runescape.com/game-session/v1/sessions`. We require a successful
exchange of the complete, unchanged ID token and a successful character listing
using the resulting game session before saving credentials or reporting success.
Rejection at either step leaves prior credentials unchanged. The token's nickname
is only used for a status message after those server operations have succeeded;
character IDs/names come from the authenticated server response.

This deliberately relies on Jagex correctly validating tokens and authorizing
session creation. We have not independently established every server-side
validation rule. If that endpoint were to accept forged tokens, the helper has
no independent signature check to compensate. This is a thin exchange helper,
not a standalone OIDC verifier or an identity provider for other applications.

The helper neither refreshes tokens nor checks a saved game session's validity
before launch; reauthorize when the client rejects a session.

## Callback lifetime and concurrency

Only one authorization runs per data directory, enforced with a kernel `flock`
held until it finishes. A second lock serializes short callback/pending-state
operations, with bounded contention waiting. Lock files are persistent inodes:
removing them would allow processes to lock different files under the same name.

The authorizer publishes private pending state before opening the browser.
`handle-url` requires both a live authorizer lock and unexpired pending state,
validates state, and records at most one response. Browser delivery or manual
URL consumption closes further delivery. Both input paths subsequently undergo
the same token checks. The callback wait expires after five minutes, even with
closed stdin or a partially typed line. HTTP operations have separate 30-second
socket timeouts; character selection is interactive and is not covered by the
browser callback deadline.

Normal completion, exceptions, Ctrl-C, and SIGTERM clean pending/callback files
and release locks. SIGKILL/power loss can leave files, but the kernel releases
the lock: callbacks reject that stale attempt and the next authorization replaces
it. Cleanup can fail if storage becomes inaccessible or a callback process holds
the guard too long; stale files still do not establish a live authorizer. As with
any atomic commit, cancellation after credentials were replaced cannot promise
the prior credentials are still installed.

## Local trust boundary

State lives under the user's private `jagex-auth` data directory. Private JSON
reads reject symlinks, non-regular files, other owners, loose permissions, and
oversized files. Writes use unique `0600` temporaries and atomic replacement.
Credentials are passed to clients as environment variables, never evaluated as
shell code or embedded in arguments or Nix outputs. Client arguments are not
shell-expanded.

This does not protect against a compromised process with the same UID, an
untrusted client executable, an administrator, or a compromised browser. Those
can read session files or process environments. The browser URL handler invocation
itself carries a secret URL as an argument; avoid recording process arguments or
shell history containing callback URLs. Keep HOME/XDG paths and the software
installation trusted. The installed Nix command disables Python's implicit
current-directory import path; running it in a downloaded project must not load
that project's code. Direct `python3 -m jagex_auth` usage intentionally loads the
source tree and requires trusting that tree. Deleting local credentials does
not revoke a server-side session.

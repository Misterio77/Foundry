# Authentication security model

This is an unofficial client for Jagex's existing desktop-launcher authentication
flow, not a separately registered OAuth application. Real login/client smoke
verification of this refactor is still pending. Do not include tokens, callback
URLs, credential files, or HTTP response bodies in reports.

## Protocol and local validation

The following public provider metadata was checked on 2026-10-16:

- Discovery: <https://account.jagex.com/.well-known/openid-configuration>
- Issuer: `https://account.jagex.com/` (including the trailing slash)
- Authorization endpoint: `https://account.jagex.com/oauth2/auth`
- JWKS: <https://account.jagex.com/.well-known/jwks.json>
- Advertised ID-token signing algorithm: `RS256`
- `id_token` is among the advertised response types.

The public JWKS inspected that day has an RSA signing key with `kid`, `use=sig`,
and `alg=RS256`. We require one matching RSA key ID and RS256 only. Optional
`use`/`alg` fields may be absent, but incompatible values or `key_ops` without
verification permission are rejected. A provider key rotation is handled by fetching JWKS anew for each
login, not by pinning a particular key. Changes in provider metadata/key policy
may require an update. We do not follow token-supplied `jku`/`x5u` URLs, discover
arbitrary issuers, or follow HTTP redirects for authentication requests. HTTPS
certificate verification uses Python's configured trust store.

`authorize` requests an ID token for
`com_jagex_auth_desktop_launcher_rs_hub`, with a fresh unpredictable state and
nonce. The browser response must be a state-bound URL, either exactly
`rshub://auth/callback` or the configured HTTPS successful-login URL, with the
response in the fragment. Query parameters and alternate paths/origins are
rejected. Raw-token paste is intentionally unsupported: it discards the URL's
state binding. Duplicate parameters, provider errors, missing tokens, oversized
inputs, and malformed input are rejected without echoing secrets. Manual terminal input
has echo disabled while waiting; settings are restored on completion, timeout,
or cancellation. A browser response already delivered wins over concurrent
terminal input.

Before exchanging the token for a game session, PyJWT with cryptography verifies
its RSA signature using the fixed Jagex JWKS endpoint, issuer, audience, required
claims, expiration, issued-at time, and optional not-before time. Timestamps must
be integer NumericDates; a 30-second clock skew allowance applies. We additionally
check the nonce, nonempty subject/nickname, and authorized party (`azp`) if
present or if multiple audiences are returned. Algorithm substitution, unknown
or duplicate key IDs, and invalid/missing claims fail closed.

We do not claim to know every validation performed by Jagex's game-session
endpoint. Local checks do not rely on an undocumented server-validation promise.
The session exchange and character listing still require trusting Jagex and its
HTTPS endpoints. The helper neither refreshes tokens nor checks a saved game
session's validity before launch; reauthorize when the client rejects a session.

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
installation trusted. Deleting local credentials does not revoke a server-side
session.

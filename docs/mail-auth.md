# Mail and DAV authentication

Personal mail stays on simple-nixos-mailserver (Postfix/Dovecot); calendars and
contacts stay on Radicale. Mail and DAV can share one Gablogin OAuth grant, but
have independent access policies. DAV clients can use OAuth or app passwords;
the browser UI uses Gablogin SSO on the same hostname.
IMAP 993, SMTP submission 465 and DAV remain restricted to the tailnet. Public
SMTP 25 does not offer authentication.

## Identity and authorization

The **Mail and DAV** application admits members of either `personal-mail` or
`dav-users`. These are separate permissions:

- `personal-mail` grants the existing `hi@m7.rs` mailbox, never a mailbox derived
  from an editable profile email.
- `dav-users` grants a user's own calendars and address books, via OAuth or an
  Authentik app password, or browser SSO. It does not grant mailbox access.

The blueprint creates the groups but does not assign membership. Add intended
DAV users to `dav-users`; `gabriel` needs both groups to use both services.
The OAuth client ID/application slug `personal-mail` and DAV application slug
`personal-dav` are retained for compatibility, not as authorization rules.

The public `personal-mail` OAuth client uses authorization code + PKCE,
a five-minute access token and a thirty-day refresh token. The mail scope mapping
emits `mail_account = hi@m7.rs` and `mail_access = allowed` only for active group
members. Dovecot checks these through Authentik's bearer-authenticated userinfo
endpoint for each new OAuth authentication. Only this provider has that mapping.
Userinfo rejects expired/revoked access tokens, refresh tokens and ID tokens;
there is no confidential introspection credential or locally distributed JWT key.
Revocation does not terminate an already-authenticated IMAP connection.

For DAV bearer authentication, nginx uses Authentik's existing embedded proxy
outpost. The mail OAuth provider authorizes the DAV proxy provider to introspect
its tokens through `jwt_federation_providers`; no extra service or shared secret
is needed. Clients request `profile` and `ak_proxy` for the outpost's claims.
The custom `foundry-dav-identity` profile mapping supplies
`X-Foundry-DAV-Principal` only for active `dav-users` members; otherwise it is
empty. This is required because native federated bearer authentication does not
recheck the DAV application's policy. The mapping runs after `ak_proxy` and
replaces any same-named header supplied through user/group attributes.
Vdirsyncer's generic DAV token-command patch fetches the access token from oama
and refetches/retries once on HTTP 401. Google token-command support is unchanged.

A DAV-only user may request the combined scopes but receives no `mail_account`
or `mail_access` claims. DAV-only clients can also omit the mail scope entirely.
OAuth support requires a client that supports a configurable provider; app
passwords remain the broadly compatible option.

The outpost caches successful Authorization headers for 60 seconds. Requests with
an Authorization header remain session-independent: nginx strips incoming proxy
cookies and suppresses the outpost's Set-Cookie headers. An existing browser
session cannot rescue invalid explicit credentials or extend their cache window.
Explicitly revoked/expired access tokens can therefore remain
usable for approximately one cache interval. Group removal does not revoke existing
access or refresh tokens, and the refresh grant does not recheck the application's
group policy. Revoke both access and refresh tokens when removing access; don't
rely on group removal followed by waiting five minutes. Revoking only refresh
tokens stops renewal but need not invalidate already-issued access tokens.
Authentik's native introspection also accepts refresh tokens; clients must send
only `oama access` output, never refresh tokens.

For other DAV clients, Basic authentication still uses Authentik's embedded proxy
outpost and the `personal-dav` application. Supply the **Authentik username and
app password**, not the account password, on each request. App-password revocation
is also subject to the 60-second header cache, not a browser session. The proxy
provider issues five-minute tokens independently of the one-year ceiling on
app-password credentials.

After any authentication path succeeds, nginx takes the DAV principal only
from the outpost's response, passes it as `X-Remote-User` to loopback-only Radicale,
and strips Authorization and cookies before proxying to Radicale. Radicale
explicitly uses `owner_only` rights.
Client-supplied identity headers cannot select a user; an empty/missing trusted
principal cannot access collections. Unauthenticated HTML GET/HEAD navigation can
redirect to browser SSO; DAV methods and non-HTML requests receive authentication
challenges. On DAV resources, an explicit invalid Authorization header always
receives 401, even with a valid browser cookie or HTML Accept header.

New principals default to the user's immutable Authentik UUID, independent of
username/email changes. An administrator may set the user attribute
`dav_principal` to preserve an existing storage namespace: `gabriel` has
`dav_principal: hi@m7.rs`. This is live identity data, not a blueprint migration.
Treat `dav_principal` and `additionalHeaders` as administrator-controlled
attributes; never expose them in self-service prompts or delegated user editing.
Clients should discover their principal from `https://dav.m7.rs/`.

The `personal-mail` and `dav-users` groups permit app-password lifetimes up to
365 days; choose an expiry explicitly when creating one. This ceiling covers all app passwords
created by group members, not just DAV, and does not extend existing credentials.

The SNM password database is retained for service senders. The personal mailbox
has a locked password marker and only accepts OAuth. Radicale no longer uses its
htpasswd file. No collections or mail storage paths change.

## Browser access and session termination

The **Radicale** Gablogin dashboard tile launches
`https://dav.m7.rs/.web/`. It remains tailnet-only. Radicale's built-in UI manages
collections and imports/exports; it is not a full calendar/contact frontend.
The native outpost handles the browser OAuth flow and proxy cookie through
`/outpost.goauthentik.io/`. Radicale's `prefer_browser_login` setting lets its
initial principal-discovery request include that cookie without a second login.

Browser sessions are independent credentials, not a side effect of app-password
or bearer authentication. Revoking an app password/access token does not terminate
an independently established browser session. Conversely, browser logout does
not revoke independent app passwords or OAuth refresh tokens.

Authentik browser logout and administrative session termination send a native
websocket back-channel event to the embedded outpost. It deletes matching
PostgreSQL-backed proxy sessions by `sid`; captured-cookie replay then fails
without relying on the browser clearing its cookie. Other sessions and users are
not terminated. Treat group membership, account status and principal changes as
requiring explicit browser-session termination rather than assuming continuous
policy re-evaluation. To remove every authentication path, terminate browser
sessions and revoke access/refresh tokens and app passwords as appropriate.

## Provisioning and client setup

Deploy per-user nginx routing before admitting additional DAV users. The old
fixed-principal configuration sends every authenticated user to `hi@m7.rs`.

For a fresh installation or a client that needs authorization:

1. Deploy Alcyone and wait for the Authentik blueprint to apply. Confirm `gabriel`
   belongs to both `personal-mail` and `dav-users`, has `dav_principal: hi@m7.rs`,
   and the embedded outpost has the DAV provider assigned. Other DAV users need
   only `dav-users`; leave their principal override unset for UUID-based storage.
2. Activate the updated Home Manager configuration on Atlas/Maia and authorize
   (or reauthorize existing mail credentials to grant the proxy scopes):

   ```sh
   oama authorize gablogin hi@m7.rs --nohint
   ```

   Sign in as `gabriel`. The callback is `http://127.0.0.1:8765/callback`.
   The client requests `openid profile offline_access urn:ietf:params:oauth:scope:mail ak_proxy`.
   Mail sync, submission and both DAV syncs serialize `oama access` with the same
   `$XDG_RUNTIME_DIR/oama-personal.lock`. This prevents parallel clients from
   racing a rotating refresh token. USP and MGC likewise share locks between mail
   and calendar, using `oama-usp.lock` and `oama-mgc.lock` in the same directory;
   unrelated accounts do not block each other. Restart aerc after switching accounts.
3. Other DAV clients use `https://dav.m7.rs/`, their own **Authentik username**,
   and a dedicated app password. Prefer a separate app password per device.
   OAuth-capable clients use the same public client ID and callback, requesting
   `openid profile offline_access ak_proxy` (plus the mail scope if wanted).
   Never substitute an account password or use another user's storage URL.
   The personal vdirsyncer accounts no longer read `dav.m7.rs/hi@m7.rs` from pass.

Keep existing collections; don't delete local sync state to change credentials.
A brief sync outage can occur between server/client activation and credential
setup. Mail delivery itself does not depend on interactive OAuth login.

## Live acceptance

Verify a real IMAP sync, SMTP submission, and CalDAV/CardDAV discovery and sync.
Live acceptance must cover DAV-only, mail-only and non-member users, wrong
passwords/tokens, expired and revoked access tokens, refresh-token rotation,
DAV read/write and cross-user isolation with both OAuth and app passwords, and
revocation with and without an existing proxy cookie. Also confirm ports 465/993
and DAV remain inaccessible outside the tailnet and SMTP 25 still lacks AUTH.
Builds and mocked protocol tests do not establish those production results.

### Deployed DAV verification

On 2026-11-07, the deployed nginx/outpost/Radicale stack passed:

- Authorization code + PKCE and refresh through the shared public OAuth client
  for a DAV-only user.
- Principal discovery, calendar/address-book creation, event/contact writes and
  reads for two distinct users under both bearer tokens and app-password Basic.
  The second user's bearer token came from the native proxy's OAuth grant.
- Cross-method access to the same user's collections, with cross-user reads,
  writes, discovery and forged identity headers denied. Neither test identity
  could access `gabriel`'s existing namespace.
- Access-token and app-password revocation after waiting 65 seconds for the
  header cache. Forged cookies did not restore access; independent credentials
  and the other user continued working. Header-authenticated DAV responses did
  not expose Set-Cookie.

Disposable collections, credentials and the second account were removed, and
`test`'s original membership was restored. Existing user collections were not
modified. This does not complete the broader mail/network/expiry checklist above.

### Deployed browser SSO verification

On 2026-11-07, after deploying browser SSO on the same `dav.m7.rs` hostname:

- Two users in three independent browser sessions launched the actual Radicale
  collections UI from the Gablogin dashboard without a second login. Each
  discovered their own UUID principal.
- Requests authenticated with captured browser cookies created calendars and an
  address book, wrote/read events and contacts, and shared storage with the same
  user's other browser session and app password.
- Cross-user reads/writes and forged identity headers were denied; existing
  `gabriel` collections were inaccessible and untouched. Valid explicit header
  credentials selected their own identity even with another user's browser cookie.
- Invalid explicit Basic/Bearer credentials received 401 with a valid browser
  cookie, including HTML navigation. After 65 seconds, revoked app passwords and
  access tokens also failed with that cookie; the independent browser session
  remained valid. Header-authenticated responses did not mint session cookies.
- Browser logout rejected replay of the captured DAV cookie in approximately
  0.08 seconds; administrative session termination did so in approximately
  0.12 seconds. Other browser sessions/users and independent app passwords kept
  working. These timings are observations, not a guaranteed delivery bound.

Disposable collections, credentials, peer account and browser sessions were
removed; `test`'s original group membership was restored. The dashboard launch
URL also needed a one-time live API update because deployment alone had not
updated that existing application; its final value is declared in the blueprint.

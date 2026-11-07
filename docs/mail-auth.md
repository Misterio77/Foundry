# Mail and DAV authentication

Personal mail stays on simple-nixos-mailserver (Postfix/Dovecot); calendars and
contacts stay on Radicale. The personal mail and DAV clients share Gablogin OAuth
tokens through oama. DAV also accepts app passwords for other clients.
IMAP 993, SMTP submission 465 and DAV remain restricted to the tailnet. Public
SMTP 25 does not offer authentication.

## Identity and authorization

Only members of Authentik's `personal-mail` group may access the new applications.
Membership grants the existing `hi@m7.rs` mailbox and DAV principal; it does not
use the user's editable profile email. The blueprint does not assign membership;
on a fresh installation, add `gabriel` after `Foundry - personal mail and DAV`
applies.

For mail, the public `personal-mail` OAuth client uses authorization code + PKCE,
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
is needed. The client requests `profile` and `ak_proxy` for the outpost's claims.
These are combined mail/DAV credentials: the outpost does not enforce a separate
DAV resource scope on federated tokens. Vdirsyncer's generic DAV token-command
patch fetches the access token from oama and refetches/retries once on HTTP 401.
Google token-command support is unchanged.

The outpost caches successful Authorization headers for 60 seconds. DAV is
header-only for both bearer tokens and app passwords: nginx strips incoming proxy
cookies and does not forward the outpost's Set-Cookie headers, so cookies cannot
extend that window. Explicitly revoked/expired access tokens can therefore remain
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

After either authentication path succeeds, nginx supplies the fixed `hi@m7.rs`
identity to loopback-only Radicale and strips the Authorization header.
Client-supplied identity headers cannot select a user. Missing/invalid credentials
receive authentication challenges, never a login-page redirect.

The `personal-mail` group permits app-password lifetimes up to 365 days; choose
an expiry explicitly when creating one. This ceiling covers all app passwords
created by group members, not just DAV, and does not extend existing credentials.

The SNM password database is retained for service senders. The personal mailbox
has a locked password marker and only accepts OAuth. Radicale no longer uses its
htpasswd file. No collections or mail storage paths change.

## Provisioning and client setup

For a fresh installation or a client that needs authorization:

1. Deploy Alcyone and wait for the Authentik blueprint to apply. Confirm `gabriel`
   belongs to `personal-mail` and the embedded outpost has the DAV provider assigned.
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
3. Other DAV clients may continue using `https://dav.m7.rs`, username `gabriel`,
   and a dedicated app password. Prefer a separate app password per device.
   The personal vdirsyncer accounts no longer read `dav.m7.rs/hi@m7.rs` from pass.

Keep existing collections; don't delete local sync state to change credentials.
A brief sync outage can occur between server/client activation and credential
setup. Mail delivery itself does not depend on interactive OAuth login.

## Live acceptance

Verify a real IMAP sync, SMTP submission, and CalDAV/CardDAV discovery and sync.
Live acceptance must cover allowed and non-member users, wrong passwords/tokens,
expired and revoked access tokens, refresh-token rotation, DAV read/write, and
revocation with and without an existing proxy cookie. Also confirm ports 465/993
and DAV remain inaccessible outside the tailnet and SMTP 25 still lacks AUTH.
Builds and mocked protocol tests do not establish those production results.

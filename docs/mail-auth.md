# Mail and DAV authentication

Personal mail stays on simple-nixos-mailserver (Postfix/Dovecot); calendars and
contacts stay on Radicale. Both use Gablogin, but clients authenticate differently.
IMAP 993, SMTP submission 465 and DAV remain restricted to the tailnet. Public
SMTP 25 does not offer authentication.

## Identity and authorization

Only members of Authentik's `personal-mail` group may access the new applications.
Membership grants the existing `hi@m7.rs` mailbox and DAV principal; it does not
use the user's editable profile email. Add `gabriel` to this group after the
`Foundry - personal mail and DAV` blueprint applies. The group starts empty.

For mail, the public `personal-mail` OAuth client uses authorization code + PKCE,
a five-minute access token and a thirty-day refresh token. The mail scope mapping
emits `mail_account = hi@m7.rs` and `mail_access = allowed` only for active group
members. Dovecot checks these through Authentik's bearer-authenticated userinfo
endpoint for each new OAuth authentication. Only this provider has that mapping.
Userinfo rejects expired/revoked access tokens, refresh tokens and ID tokens;
there is no confidential introspection credential or locally distributed JWT key.
Revocation does not terminate an already-authenticated IMAP connection.

For DAV, nginx delegates authentication to Authentik's embedded proxy outpost,
using the `personal-dav` application. Clients send Basic authentication with their
**Authentik username and app password**, not their account password. On success,
nginx supplies the fixed `hi@m7.rs` identity to loopback-only Radicale and strips
the Authorization header. Client-supplied identity headers cannot select a user.
Missing/invalid credentials receive a Basic challenge, never a login-page redirect;
an unavailable outpost fails closed. Cookies returned by the outpost are forwarded
to clients to reduce repeated authentication work. Existing proxy sessions can
outlive the credential that created them; don't assume app-password deletion
immediately invalidates every session.

The `personal-mail` group permits app-password lifetimes up to 365 days; choose
an expiry explicitly when creating one. This ceiling covers all app passwords
created by group members, not just DAV, and does not extend existing credentials.

The existing SNM password database is retained for service senders and rollback,
including the old personal mail password for now. Radicale no longer uses its
htpasswd file. No collections or mail storage paths change.

## Rollout

1. Deploy Alcyone, wait for the Authentik blueprint to apply, and add `gabriel` to
   `personal-mail`. Confirm the embedded outpost has the DAV provider assigned.
2. In Gablogin, create a dedicated app password for DAV. Save it without printing
   it to the terminal:

   ```sh
   pass insert dav.m7.rs/hi@m7.rs
   ```

   Other DAV clients use server `https://dav.m7.rs`, username `gabriel`, and that
   app password. Prefer a separate app password per device where practical.
3. Activate the updated Home Manager configuration on Atlas/Maia and authorize:

   ```sh
   oama authorize gablogin hi@m7.rs --nohint
   ```

   Sign in as `gabriel`. The callback is `http://127.0.0.1:8765/callback`.
   The client requests `openid offline_access urn:ietf:params:oauth:scope:mail`.
   Mail sync and submission serialize `oama access` with the same per-user lock
   to avoid refresh-token rotation races. Restart aerc after switching accounts.
4. Verify a real IMAP sync, SMTP submission, and CalDAV/CardDAV discovery and sync.
   Keep existing collections; don't delete local sync state to change credentials.
   A brief sync outage is expected between server/client activation and credential
   setup. Mail delivery itself does not depend on interactive OAuth login.

Live acceptance must cover allowed and non-member users, wrong passwords/tokens,
expired and revoked access tokens, refresh-token rotation, DAV read/write, and
revocation with and without an existing proxy cookie. Also confirm ports 465/993
and DAV remain inaccessible outside the tailnet and SMTP 25 still lacks AUTH.
Builds and mocked protocol tests do not establish those production results.

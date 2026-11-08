# Mail and DAV authentication

Mail stays on simple-nixos-mailserver (Postfix/Dovecot); calendars and contacts
stay on Radicale. Both share one Gablogin OAuth authorization, but have separate
application entitlements and resource identities. Both also accept Authentik app
passwords for clients without configurable OAuth support.

IMAP 993, SMTP submission 465 and DAV are restricted to the tailnet. Public SMTP
25 does not offer authentication. DAV has no browser UI or cookie authentication.

## Configuration boundaries

- `authentik/authorization.yaml`: groups and the common application-access policy.
- `authentik/mail.yaml`: Mail's `access` entitlement, mailbox claims and the
  app-password provider.
- `authentik/dav.yaml`: Radicale's `access` entitlement, principal claims and the
  embedded proxy outpost.
- `authentik/mail-and-dav.yaml`: shared OAuth client, PKCE policy and federation.
- `services/mail.nix`: mailbox provisioning, aliases, delivery and Dovecot auth.
- `services/radicale.nix`: trusted-header authentication, storage and network ACLs.
- `home/gabriel/features/productivity/accounts/personal.nix`: Oama and clients.

These are static blueprints; mailbox declarations do not generate Authentik users
or attributes. See [Gablogin authorization](authentik.md#access) for all apps.

## Entitlements and principals

Mail (`mail`) and Radicale (`radicale`) each own an `access` entitlement. Both
`trusted` and `admin` receive both entitlements; `user` and `authentik-admin` do not.
There is no mail/DAV administration role. Entitlements may also be assigned
individually, including mail-only or DAV-only access.

The shared `mail-and-dav` application checks whether the active user has either
service's `access` entitlement, and separately requires S256 PKCE. Its public
client permits authorization-code and refresh-token grants, with five-minute
access tokens and thirty-day refresh tokens. Its callback is
`http://127.0.0.1:8765/callback`.

Resource identities are administrator-managed user attributes:

```yaml
mail_principal: hi@m7.rs
dav_principal: hi@m7.rs
```

- `mail_principal` is the canonical mailbox address. It is required: absent or
  blank principals emit no mail identity claims. Neither username nor editable
  profile email selects a mailbox. The mailbox must also exist in Nix.
- `dav_principal` overrides the storage identity. Without an override, Radicale
  uses the immutable Authentik user UUID. Gabriel's override preserves the
  existing `hi@m7.rs` collections.

Do not expose these attributes, or proxy `additionalHeaders`, in self-service
prompts. Assigning the same principal to two users intentionally shares the same
resource; ordinary users should have distinct principals.

## Mail authentication and provisioning

The mail scope (`urn:ietf:params:oauth:scope:mail`) emits `mail_account` from the
principal and `mail_username` from the Authentik username, only for active users
with Mail's `access` entitlement and a configured principal.

OAuth-capable clients supply a bearer token. Dovecot validates it online through
Authentik's userinfo endpoint, checks `mail_account`, and selects that mailbox.
There is no locally distributed JWT key or confidential introspection credential.

Other clients supply their Authentik username and **app password**, not their
account password. Dovecot exchanges those credentials through the separate
`mail-app-passwords` password-grant client, checks `mail_username`, then selects
`mail_account`. This provider is attached to the Mail application and uses the
same entitlement and identity mapping as the shared client.

To provision another user's inbox:

1. Add a canonical account to `mailserver.accounts` in `services/mail.nix`, with
   `hashedPassword = "!"` and any delivery aliases. Deploy the mail configuration.
2. Set the user's `mail_principal` to that exact canonical address in Authentik.
3. Grant Mail's `access` entitlement, usually through `trusted` or `admin`.
4. Configure OAuth using the canonical address, or app-password authentication
   using the Authentik username.

Aliases belong to Postfix/Nix, not Authentik. The existing domain catch-alls still
route unmatched addresses to `hi@m7.rs`; explicit recipients can have separate
mailboxes. Service senders retain their independent local SMTP credentials.
Granting an entitlement does not provision an inbox or change delivery routing.

## DAV authentication

nginx authenticates each DAV request through Authentik's embedded proxy outpost.
The outpost accepts username/app-password Basic authentication and bearer tokens;
`jwt_federation_providers` permits tokens from the shared OAuth client.

The custom profile mapping emits `X-Foundry-DAV-Principal` only for active users
with Radicale's `access` entitlement, otherwise an empty principal. This mapping
is an authorization boundary: native federated bearer authentication does not
recheck the Radicale application's admission policy. It runs after `ak_proxy`
and overrides headers supplied by user/group attributes.

nginx takes the principal only from the outpost response, passes it as
`X-Remote-User` to loopback-only Radicale, and strips Authorization and cookies.
Radicale uses `owner_only` rights. Client-supplied identity headers cannot select
a different user's collections, and an empty principal cannot access them.

Cookies are never forwarded to the outpost. Unauthenticated requests receive
Basic/Bearer challenges, not browser redirects, even for HTML navigation.
Radicale's web UI is disabled. Clients discover their own principal from
`https://dav.m7.rs/` rather than hardcoding storage URLs.

## Client setup and credential lifetime

Authorize the shared client once:

```sh
oama authorize gablogin hi@m7.rs --nohint
```

The configured scopes are
`openid profile offline_access urn:ietf:params:oauth:scope:mail ak_proxy`.
DAV-only clients can omit the mail scope. Requesting a scope does not grant its
underlying entitlement.

Mbsync uses XOAUTH2, msmtp uses OAUTHBEARER, and vdirsyncer obtains bearer tokens
through its token command. All personal-account clients serialize `oama access`
with `$XDG_RUNTIME_DIR/oama-personal.lock` to avoid rotating-refresh-token races.
Vdirsyncer refetches the token and retries once after HTTP 401. Keep collections
and local sync state when changing credentials.

For app-password clients, use an individual credential per device and explicitly
choose its expiry. The `trusted` and `admin` groups permit user-created tokens up
to 365 days; this is a group-wide ceiling, not a service-scoped credential grant.
It does not extend existing credentials.

The outpost caches successful Authorization headers for 60 seconds, so revoked
credentials may work for approximately one cache interval. Its native
introspection also accepts refresh tokens; clients must send only access tokens.
Dovecot's online validation rejects expired/revoked access tokens, refresh tokens
and ID tokens, but revocation does not terminate an authenticated IMAP connection.

Entitlement/group removal is not token revocation. Refresh grants do not rerun
application admission, and already-issued tokens can retain claims. Revoke access
and refresh tokens, or app passwords, when removing a client's access; terminate
established service sessions separately if immediate removal is needed.

## Acceptance checks

After deployment, verify actual IMAP sync, SMTP submission, and CalDAV/CardDAV
read/write. Check separate users/mailboxes and DAV collections, mail-only and
DAV-only entitlements, no entitlement, inactive users, and missing mail principals.
Exercise OAuth and app passwords, refresh, incorrect/revoked credentials,
principal-header spoofing, and cookie-only requests. Confirm public SMTP lacks
AUTH and submission/IMAP/DAV remain tailnet-restricted.

Local expression checks and Nix builds do not establish protocol or live
acceptance. Temporary tests belong outside the repository until there is a
shared Authentik test harness.

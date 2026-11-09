# Mail and DAV authentication

Mail stays on simple-nixos-mailserver (Postfix/Dovecot); calendars and contacts
stay on Radicale. Both share one Gablogin OAuth authorization, but have separate
application entitlements and resource identities. Both also accept Authentik app
passwords for clients without configurable OAuth support.

IMAP 993, SMTP submission 465 and DAV are restricted to the tailnet. Public SMTP
25 does not offer authentication. Radicale's collection-management UI uses Gablogin
browser SSO on the same tailnet-only DAV hostname.

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

Explicit Authorization credentials take precedence over browser cookies: nginx
removes cookies before header authentication and suppresses session-cookie issuance.
Invalid Basic/Bearer credentials therefore receive 401 even alongside a valid
browser cookie. Without an Authorization header, an outpost browser session may
authenticate the request.

Only unauthenticated HTML GET/HEAD navigation redirects to Gablogin. DAV methods
and non-HTML requests receive Basic/Bearer challenges. Clients discover their own
principal from `https://dav.m7.rs/` rather than hardcoding storage URLs.

## Browser collection management

The **Radicale** dashboard tile opens `https://dav.m7.rs/.web/`. Its built-in UI
manages calendars/address books and imports/exports; SOGo remains the richer
Mail/DAV frontend. `prefer_browser_login` allows the UI's initial discovery request
to use its outpost cookie without another credential prompt.

The existing embedded outpost handles login at `/outpost.goauthentik.io/`; no new
OAuth client, custom session service or public network exposure is introduced.
Current DAV entitlements, UUID/principal overrides and SOGo/shared-client federation
remain unchanged. Private collections retain `owner_only` rights; native mapped
shares provide explicit access through aliases in the recipient's own DAV home.

Browser sessions are independent credentials. Revoking an app password or OAuth
grant does not end an independently established browser session, and browser logout
does not revoke independent client grants. Authentik's native outpost back-channel
logout invalidates matching proxy sessions. Treat entitlement, account-status and
principal changes as requiring explicit session termination rather than assuming
continuous authorization re-evaluation.

The original integration (`1f4ddbf0`, later removed in `8da12022`) had live multi-user,
credential-precedence and cookie-replay/logout checks. That historical evidence is
not a substitute for acceptance of this restoration.

## Usernames and Apple configuration profiles

The web heading displays the Gablogin **username**, while DAV principal URLs,
collection ownership and sharing continue to use the UUID/`dav_principal` identity.
Collection titles are unchanged. The Authentik mapping emits a separate percent-encoded
`X-Foundry-DAV-Username` header; nginx takes it only from the authentication response
and overwrites any client-supplied value before forwarding. The Radicale patch uses
it solely for presentation/profile login fields with trusted-proxy authentication.
It never changes the authenticated principal or authorizes a request.

The web UI's **Mobileconfig** download configures CalDAV and CardDAV with that
username, `dav.m7.rs`, HTTPS port 443, and `/` for principal discovery. Profile
identifiers remain based on the stable DAV principal. No password or OAuth token is
embedded: use a dedicated Authentik app password when the device asks for credentials.
The device still needs tailnet access; the profile does not configure VPN access.
Actual Apple-device installation remains an acceptance check.

After deploying the new username mapping, use a fresh Radicale SSO session if the
heading still shows the principal. Missing username claims fall back to the principal,
so an older session can still generate a profile with an unsuitable login name.

## Sharing calendars and address books

Radicale 3.9.0 provides native **Share by Map** management in its web UI. Mapped
sharing and user-created mappings are enabled; token/link sharing remains disabled.
No shared credentials or broader rights file are needed. New API shares default to
read-only; owners can deliberately grant read/write in the UI.

1. On an owned collection, open **Share**, then **New Share by Map**. Search/select
   the recipient's exact Gablogin username in **Share User**. The picker resolves it
   to their existing UUID/`dav_principal`; it does not change storage identities.
   Unknown names and partial matches cannot be submitted. Existing shares retain
   their immutable principal when edited.
2. Choose permissions and leave the share enabled and not hidden. **Share Href** is
   a single collection-name component (the generated value is fine), not a full URL:
   it becomes `/<recipient-principal>/<share-href>/`.
3. The recipient opens Radicale and enables/shows the incoming share using its
   controls. Individual-recipient shares start disabled and hidden on their side.
4. Once accepted and shown, the alias is returned by normal depth-one home discovery.
   Refresh/reconnect clients as needed. This matches SOGo's existing direct-child
   discovery model; live SOGo UI acceptance is still required, not established by
   protocol tests alone.

Sharing grants access to the existing collection, not a copy. Owners can change
permissions, disable or delete the mapping. Read/write recipients can change/delete
items; deleting a share through the sharing UI does not delete the owner's collection.
Recipients cannot elevate permissions or re-share another owner's private collection.
The picker is advisory, not a new authorization mechanism: the native sharing API
still takes principals and enforces its own permissions. Principal changes require
reviewing existing shares as well as client configuration.

The same-origin `GET /.sharing-users` endpoint is tailnet-only and authenticated by
the existing DAV outpost. nginx strips credentials and overwrites identity headers
before forwarding to Authentik's internal `/-/foundry/dav-users/` view. Public
Authentik ingress blocks that route and strips the internal gateway marker; the DAV
outpost ingress strips the marker too. The view rechecks the caller's current active
status, DAV entitlement and username/principal pairing, then lists only active human
accounts with Radicale's `access` entitlement. Service accounts, invalid principals
and duplicate/ambiguous principals are omitted. It exposes only username/principal
pairs, including the caller for self-targeted calendar conversions. DAV users can
therefore discover one another's usernames and principals (some legacy principals
are email-shaped); no additional profile fields are exposed.

Results are not HTTP-cached or stored in browser persistence. The picker reloads on
each dialog opening, cancels outstanding lookups when closed, and refuses creation
if lookup fails; it never silently interprets an unknown name as a principal. A stale
SSO session lacking the username claim needs a fresh login. Directories larger than
500 active human accounts fail closed rather than presenting a partial list. No
new daemon, API credential or broader Authentik user-list permission is required.

Share metadata uses Radicale's `files` backend under
`/var/lib/radicale/collections/collection-db/files`, inside the existing persistent
and Borg-backed DAV tree. Restore share metadata and collection data together.
Rolling configuration back to disabled sharing hides mappings but does not erase
that persisted metadata.

Cookie-authenticated requests other than GET/HEAD/OPTIONS require the exact Origin
`https://dav.m7.rs`; missing, null and cross-origin values are denied. This protects
the form-capable sharing API from cross-site writes. Explicit Authorization requests
still use their own credentials independently of cookies and do not require Origin.

Isolated tests against the packaged Radicale verified recipient acceptance/home
listing, read-only/read-write access, unrelated-user and escalation denial, disabled
token sharing, immediate mapping revocation, restart persistence, and owner-data
preservation after share deletion. An actual nginx fixture checked the evaluated
origin maps. These are not production SSO or browser-UI acceptance results.

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
principal-header spoofing, and cookie-only requests. For browser SSO, verify dashboard
launch without a second login, collection creation, cross-user isolation, invalid
header rejection despite valid cookies, and no session cookies from header auth.
Replay captured cookies after logout and administrative session termination while
checking independent browser sessions and client grants remain usable. Use disposable
collections only. Confirm public SMTP lacks AUTH and submission/IMAP/DAV remain
tailnet-restricted.

Local expression checks and Nix builds do not establish protocol or live
acceptance. Temporary tests belong outside the repository until there is a
shared Authentik test harness.

# Mail, DAV, and SOGo: authentication boundaries

These are the existing central-credential integrations, not a completed universal
Gablogin API layer. See [the service inventory](authentik.md) for the fleet and
[the alternatives](todo/gablogin-api-auth.md) for decisions still under evaluation.

The comparison baseline is `5b0316a5`; current checked-in scope names include the
`vksqkonk` scoped-client change. Configuration, upstream-code inspection, isolated
tests, and live client acceptance are different kinds of evidence.

## Who authenticates what?

| Consumer | Credential | Validation and identity |
| --- | --- | --- |
| IMAP/SMTP OAuth client | Authentik access token | Dovecot calls userinfo; `mail_account` selects mailbox |
| IMAP/SMTP legacy client | Authentik username + app password | Separate `mail-app-passwords` password-grant provider; username checked, mailbox mapped |
| DAV OAuth client | Authentik access token | Outpost introspection/federation; trusted principal forwarded by Nginx |
| DAV legacy client | Basic username + app password | Outpost client-credentials exchange; trusted principal forwarded |
| DAV browser | Outpost session cookie | Outpost session; trusted principal forwarded |
| SOGo browser | SOGo OIDC login/session | Separate confidential client; user token delegated to mail and DAV |
| Application SMTP sender | Dedicated local SMTP credential | Existing mail-server account, outside personal Gablogin authentication |

IMAP 993, submission 465, and DAV are tailnet-restricted. Public SMTP 25 does not
offer authentication. SOGo is the web frontend at `mail.m7.rs`, not the validator
for external IMAP/SMTP clients.

## Entitlements and resource identities

Mail and Radicale each own an `access` entitlement. `trusted` and `admin` receive
both; individual grants can permit only one. There is no Mail/DAV admin role.
SOGo admission requires both services.

- **Mail:** `mail_principal` must be a nonblank canonical mailbox address. Missing
  principals emit no mail identity. Username and editable profile email do not
  select the mailbox. Nix must separately declare the mailbox and delivery aliases.
- **DAV:** `dav_principal` overrides the immutable Authentik UUID. It selects storage
  identity, ownership, and share recipients. Username is a separate display/login
  field, not an authorization identifier.
- **Shared principals:** mapping multiple actors to the same resource intentionally
  shares access. Changes affect existing storage URLs, shares, and identity mapping;
  they are not merely display-name edits.

Principals and proxy identity attributes must remain administrator-controlled.
Application access does not provision resources automatically.

## Shared OAuth and the scoped-client change

At the baseline, `mail-and-dav` admitted an active user with access to either
service. Mail used `urn:ietf:params:oauth:scope:mail`; DAV identity came through
`profile` and proxy mappings. There was no explicit service-consent screen.

The checked-in replacement, `gablogin-cli`, requires explicit `openid` plus one
or both service scopes, `mail` and `dav`. Authorization requires access to every
requested service and explicit consent. Unknown/omitted scopes, repeated scope
parameters, and normalization differences are rejected rather than silently
broadening or narrowing the request.

It is a public client with mandatory S256 PKCE, authorization-code and refresh
grants only, and the strict callback `http://127.0.0.1:8765/callback`. Access tokens
last five minutes; refresh tokens last thirty days and rotate on renewal.
`offline_access` requests renewal capability. The configured oama entry requests
`openid offline_access mail dav`; service mappings isolate the resulting claims.

Authorization requests containing `firefly` are denied. During refresh, the pinned
provider can silently discard unsupported scopes rather than return an error;
live tests confirmed that adding `firefly` did not grant it or emit its identity.

Changing configured scopes does not narrow an existing refresh grant. Narrower
access requires reauthorization and revocation of grants whose authority should
end. The existing oama patch retains replacement refresh tokens; personal clients
serialize token retrieval to avoid refresh-rotation races.

SOGo retains its own confidential OIDC client, five-minute access tokens and
one-day refresh tokens. Its current scopes include `openid profile mail dav
ak_proxy offline_access`; it is not switched to the shared CLI client.

Firefly is deliberately excluded: the client offers no `firefly` scope or Firefly
identity mapping. Firefly retains its proxy browser login and native API tokens.
Scoped Mail/DAV issuance stands alone without the broader gateway proposal.

## Mail validation

Dovecot forces online userinfo validation. The mail mapping emits `mail_account`
and `mail_username` only when the user is active, has Mail access, and has a valid
mail principal. Userinfo evaluates mappings afresh rather than simply returning
all identity claims captured at token issuance.

App passwords use the separate Mail provider, not a password grant on the shared
CLI client. Personal local mailbox passwords are locked. App-password labels do
not scope credentials to a particular service; the user's entitlements and each
consumer's validation determine access. A per-device credential limits the impact
of revoking that credential, but not inherently the services it can authenticate.

The pinned userinfo path rejects refresh and ID tokens. This does not replace an
audit of allowed issuing clients/providers and required service scopes. A valid
signature or common issuer alone is not a sufficient resource authorization rule.

Existing authenticated IMAP connections are a separate boundary: fresh online
authentication checks do not continuously reauthenticate them.

## DAV validation and browser sessions

Nginx authenticates DAV requests through the embedded outpost. Federation permits
shared-client and SOGo tokens. The DAV mapping supplies the authoritative principal;
Nginx overwrites client identity headers and forwards `X-Remote-User` to loopback-
only Radicale, stripping Authorization and cookies.

The existing Nginx configuration already provides these protections:

- Explicit Authorization removes browser cookies from the outpost request, so
  invalid explicit credentials cannot fall back to a valid browser session.
- Header-auth responses do not expose newly minted outpost session cookies.
- DAV authentication failures use 401/challenges instead of browser login HTML;
  only unauthenticated browser navigation redirects to Gablogin.
- Cookie-authenticated writes require the exact DAV Origin. Explicit credential
  requests authenticate independently of cookies.

These are existing compensations for outpost behaviour, not entirely missing
features that require a new global validator.

### Remaining validation concerns

The pinned outpost caches successful Authorization headers for roughly 60 seconds.
Its bearer path trusts active introspection results; core introspection also
supports refresh tokens and can return claims captured at issuance. Federated
bearer authentication does not itself rerun the target application's admission
policy. Consequently:

- Renaming a scope is not proof that the consumer enforces the intended scope.
- Current entitlement/principal changes are not guaranteed to appear immediately.
- The cache interval is not a universal end-to-end revocation bound: browser
  sessions, token claims, and protocol connections have their own lifetimes.
- A resource server must distinguish access tokens from other active token types.
  Supporting refresh-token introspection in core is not intrinsically a defect;
  accepting that response as resource authorization is the relevant concern.

Our embedded outpost runs the Rust implementation. The source tree also contains
older Go proxy code; a patch to that code alone would not harden this path.

## Sharing and directory integration

Radicale retains `owner_only` rights with native Share by Map enabled. Owners can
grant read-only or read/write access; token/link sharing is disabled. Recipients
accept/show mapped shares in their own homes. This is application resource
permission management, not another Authentik entitlement.

A server-side adapter supports username-to-principal lookup for the sharing UI.
Its separate `svc-radicale-directory` Authentik account can read users and user
application visibility. Although only username/principal pairs reach the browser,
its API permissions can read broader user records, so the credential stays
server-side. Directory policy caching can delay access changes; directory lookup
is not the DAV request-authentication boundary.

Mobileconfig generation uses the Authentik username for login and embeds no
password or token. It does not provide VPN access or turn an app password into a
service-scoped credential. Sharing metadata and collection data belong together
for persistence and recovery.

## Evidence and remaining acceptance

The scoped issuance work passed live authorization, consent, claim isolation,
PKCE, refresh rotation/replay, narrowing, revocation, and negative authorization
tests. Oama was reauthorized successfully. This is not full mail/DAV/SOGo client
acceptance or proof of the proposed consumer-hardening contract.

Outstanding evaluation should cover:

- Actual IMAP sync, SMTP submission, CalDAV/CardDAV reads and writes, and SOGo
  mail/calendar/contact operations, including renewal.
- OAuth and app passwords; inactive users, removed entitlements, missing
  principals, separate users/resources, and expired/revoked credentials.
- Wrong-service/provider tokens and refresh/ID tokens at the resource endpoint,
  not merely at userinfo or the authorization endpoint.
- Invalid explicit credentials alongside valid cookies, forged identity headers,
  browser CSRF protection, and absence of usable cookies from header auth.
- Browser logout versus OAuth-grant/app-password revocation, independent sessions,
  established IMAP connections, and actual cache/expiry boundaries.
- Sharing and Apple client behaviour through the real authentication boundary,
  rather than relying only on isolated Radicale/proxy tests.

No decision has been made to replace these integrations or mandate zero caching.
A predictable, measured revocation bound is an option under discussion.

## Sources

[Mail](../hosts/nixos/alcyone/services/mail.nix),
[Radicale](../hosts/nixos/alcyone/services/radicale.nix),
[SOGo](../hosts/nixos/alcyone/services/sogo6.nix),
[Authentik blueprints](../hosts/nixos/alcyone/services/authentik/),
[personal client configuration](../home/gabriel/features/productivity/accounts/personal.nix).

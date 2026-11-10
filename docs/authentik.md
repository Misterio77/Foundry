# Gablogin: authentication across services

Gablogin centralizes identity and application admission through Authentik, but
not every application's credentials, sessions, or resource permissions. This is
an assessment of the checked-in integrations, not a claim that every configured
path has passed live acceptance.

The comparison baseline is `5b0316a5` (`main` when this assessment began).
`vksqkonk` changes shared Mail/DAV OAuth issuance and service scope mappings;
it leaves Firefly browser authentication and native API credentials unchanged.
Those changes are described separately below. Neither revision implements a
universal gateway.

- [Mail, DAV, and SOGo](mail-auth.md): protocol boundaries and credential lifetimes.
- [Directions and concerns](todo/gablogin-api-auth.md): alternatives under evaluation,
  not an approved implementation sequence.

## Intended user-facing contract

The goal is a consistent experience for people connecting to services, not
identical authentication machinery inside every service:

> Users should not need to learn each application's credential-management
> procedure. Use integrated Gablogin login or helper-managed OAuth; when neither
> fits, create an app password in Gablogin and supply it to the client.

There are two preferred paths and one shared fallback:

- **Integrated login/device approval.** Sign in or approve the device through
  Gablogin in a browser. The client manages its session or native tokens afterward;
  the user need not generate and copy an application-specific PAT.
- **OAuth through tooling such as oama.** Authorize the requested scopes through
  Gablogin in a browser, then let a helper supply access tokens and manage refresh
  for CLI tools, scripts, and unattended jobs. This is a first-class interface for
  non-interactive use, not merely a workaround for a missing login button.
- **App-password fallback for either path.** When neither integrated login nor
  helper-managed OAuth fits, create a dedicated credential centrally and enter
  the Authentik username and app password through the supported transport. Never
  substitute the account password. Clients do not need to implement all three.

Both preferred paths can involve a browser during initial authorization; their
ongoing use differs. Oama supports unattended operation after interactive consent,
not completely headless bootstrap. Refresh-grant expiry or revocation can require
reauthorization. Machine-to-machine OAuth is a separate grant/design, not implied
by using an OAuth token from a script.

This is the intended surface, not a claim of universal support today. A client
and service must both support the selected path. An ordinary API-key field does
not necessarily accept an app password, and backend OAuth support cannot add a
browser login flow to a client that lacks one.

Native OIDC, Quick Connect, proxy identity, and protocol adapters can coexist
behind this surface. Distinguish native credentials created automatically after
Gablogin approval from native credentials the user must manually generate. The
former are compatible with the vision; the latter are user-facing exceptions.

This does not promise a unified device-management screen, identical revocation
latency, or automatic revocation of every credential on browser logout. Those
lifecycle guarantees need their own decisions and evidence. Operator-managed
backend keys and service accounts are a separate integration concern; their
existence alone does not break the interactive connection experience.

## Shared foundation

Authentik owns account authentication, optional MFA, profile information, and
application entitlements. Accounts with enrolled WebAuthn or TOTP must validate
MFA. Account-password and enrolled-MFA checks protect the configured sensitive
change flows; Authentik's separate authenticator-deletion API remains a known
fresh-authentication gap. Login sessions are configured for 30 days.

Groups grant application entitlements; mappings translate them into downstream
roles. Authentik administration is separate from application administration.

| Group | Application access | Application administration |
| --- | --- | --- |
| `user` | Grafana, Immich, Jellyfin, Seerr, Calibre-Web, Firefly | None |
| `trusted` | Those services plus Mail, Radicale | None |
| `admin` | All of the above | Grafana, Immich, Jellyfin, Seerr, Firefly |
| `authentik-admin` | No application access implied | Authentik superuser only |

SOGo requires both Mail and Radicale access rather than a separate entitlement.
Individual entitlement assignments can supplement groups. An `admin` entitlement
alone does not substitute for application `access`.

Identity and resource ownership are distinct. Mail requires `mail_principal`;
DAV and Firefly use `dav_principal` and `firefly_principal`, falling back to the
Authentik UUID. Assigning the same principal to multiple actors intentionally
shares a backend identity. That does not automatically preserve distinct audit
actors or make shared-user role synchronization safe.

## Three authentication models

| Model | Flow | Who owns subsequent authentication? |
| --- | --- | --- |
| Native OIDC | Gablogin login, then application session/token issuance | Application |
| Proxy identity | Nginx asks the outpost, then forwards trusted identity | Outpost plus application-specific integration |
| Protocol integration | Dovecot validates client credentials through Authentik | Dovecot and the established IMAP/SMTP connection |

An application accepting OIDC login does not necessarily accept Authentik bearer
tokens on its API. An API request authenticated by an application session is also
not the same thing as a script using an independent API key.

## How the current user experience fits

| Surface | What the user does | Assessment against the intended contract |
| --- | --- | --- |
| Jellyfin browser/native clients | Gablogin login or Quick Connect approval | Fits without replacing Jellyfin-issued device tokens |
| Immich browser/mobile | Native OIDC login through Gablogin | Fits for those clients; manual API-key workflows remain separate |
| Grafana and Seerr browsers | Sign in through Gablogin | Fits for browser use; does not imply central API credentials |
| Calibre-Web browser | Sign in through the outpost | Fits for browser use; OPDS/Kobo are disabled, not implemented fallbacks |
| Firefly browser | Sign in through the outpost | Fits for browser use |
| Waterfly | Obtain a Firefly PAT and configure it in the client | Known exception, deliberately unchanged for now |
| Mail/DAV CLI tools and unattended jobs | Authorize through oama, then retrieve/refresh access tokens through the helper | First-class helper-managed OAuth path; full end-to-end acceptance remains pending |
| Mail/DAV clients without usable OAuth | Configure a dedicated Gablogin app password | Shared fallback; not a service-scoped OAuth grant |
| Radicale browser and SOGo | Sign in through Gablogin | Fits the browser pattern; SOGo delegates backend credentials internally |

Judge specific client workflows, not just whole applications. For example, an
Immich mobile login and an automation script asking for an Immich API key expose
different credential experiences even though both use the same service. Likewise,
oama's browser authorization is not a built-in OAuth button in every mail client.

The next proposed work is to finish acceptance of the existing Mail/DAV/SOGo
paths, not to replace working native OIDC/device flows. Firefly remains an explicit
exception; closing it later would be a focused integration decision.

## Service inventory

### Jellyfin — OIDC login and native device credentials

At `media.m7.rs`, the patched OIDC plugin handles browser login; local password
authentication is blocked by the startup guard. Native clients use Quick Connect
approval through Gablogin and receive Jellyfin tokens, not Authentik access tokens.

- Stable OIDC subject bindings select users; automatic email linking and username
  migration are disabled.
- `access` and `admin` map to Jellyfin roles at login. Both have all-library access;
  audio transcoding is enabled and video transcoding disabled.
- Our patches persist token ancestry from the originating OIDC login through
  Quick Connect descendants. Delivered back-channel logout revokes that family,
  not independent logins. Untracked old devices do not gain this guarantee.
- Independent application API keys remain, including Seerr's Jellyfin credential.

This is already a substantial integration: plugin/web patches, account guards,
profile synchronization, and persistent session lineage. Central device approval
and revocation have been added without replacing native client tokens.

### Immich — native OIDC and application-owned sessions

At `photos.m7.rs`, browser and mobile clients use native OIDC. Password login is
disabled; automatic OAuth launch and registration are enabled.

- Initial linking can use matching email, unlike integrations that require an
  existing subject binding or explicit account linking.
- Role and quota claims synchronize through OAuth login. The default quota is
  8 GiB; the configured user attribute can override it.
- Native API keys and shared links remain separate application mechanisms; there
  is no shared Authentik-bearer API gateway.
- Authentik is configured to send back-channel logout to Immich's native endpoint.
  This does not establish API-key revocation or continuous entitlement enforcement.
- Our avatar patch refreshes the profile image on OAuth login.

### Grafana — native OIDC with patched session revocation

At `dash.m7.rs`, OAuth is the only interactive login method. Basic/local login,
anonymous viewing, and insecure email-based account linking are disabled.

- `access` maps to Viewer; `admin` maps to Grafana server administrator.
- Grafana owns browser sessions. OAuth refresh is disabled and `offline_access`
  is not requested; access-token expiry does not terminate the local session.
- Our back-channel patch binds sessions to verified OIDC identity and persists
  revocation cutoffs. Delivered logout affects correlated browser sessions, not
  independent service-account tokens or already-running requests/WebSockets.
- Native service-account/API credentials remain separate.
- Additional customization synchronizes the OIDC picture claim.

Existing browser sessions intentionally do not depend on checking Authentik on
every request. Grafana's state is ephemeral across host resets: session state and
revocation markers must not be treated as independently restorable data.

### Seerr — patched OIDC and centrally supplied permissions

At `requests.m7.rs`, the package uses an experimental upstream OIDC implementation
plus local patches. Password, media-server, and Quick Connect login are disabled.

- OIDC account linking is explicit, not automatic merely because emails match.
- Authentik emits `REQUEST` or `ADMIN`. Permissions are replaced on login,
  including for the owner; local permission-edit endpoints are disabled.
- Provider logout and persistent back-channel revocation are patched in. Role
  changes are not continuously synchronized into existing sessions.
- Native API credentials remain. Seerr also holds separate Jellyfin, Sonarr, and
  Radarr keys for its backend integrations.

The maintained surface includes declarative provisioning, permission mapping,
profile synchronization, and logout. This is not an unmodified native integration.

### Calibre-Web — browser-only proxy identity

At `books.m7.rs`, Nginx authenticates requests through the outpost. Our application
patch trusts the forwarded UUID identity, not local passwords or an independent
browser session. Nginx strips Authorization and overwrites identity headers.

- Authentik UUID maps to a local account; mutable username/email do not select it.
- Authentik controls admission. New users receive viewer/download roles; existing
  local roles are preserved. There is no Authentik admin-role mapping.
- OPDS and Kobo endpoints are explicitly disabled. App-password and OAuth API
  access have not been implemented here.
- Logout delegates to the outpost.

The separate Calibre content server at `calibre.m7.rs` is tailnet-restricted and
uses its own authentication. It is not the Calibre-Web/Gablogin integration.

### Firefly — proxy browser login, native API authentication

At public `firefly.m7.rs`, the outpost authenticates browser requests. Nginx passes
trusted CGI variables to the remote-user guard; client HTTP headers cannot supply
those variables. The `user`, `trusted`, and `admin` tiers all receive application
access; only the `admin` tier receives the admin entitlement.

Public reachability does not permit anonymous financial-data access. Browser
requests still require Gablogin, and API requests still require Passport
credentials. Native PATs are now usable without tailnet membership; their
independent lifetime and revocation remain unchanged.

- `firefly_principal` or the UUID selects the financial identity. The identity
  mapping supplies display information and an admin flag; our integration
  synchronizes Firefly's owner role from that flag.
- `/api/` deliberately bypasses outpost authentication and clears the trusted
  browser identity variables. Passport accepts native PATs or its CSRF-protected
  browser API cookie.
- External clients such as Waterfly need Firefly-native credentials under this
  design. The PTAX exchange-rate job uses a SOPS-managed Firefly PAT.
- Browser logout goes through the outpost; PATs have an independent lifecycle.

This explicit browser/API split motivated the central-credential proposal. The
current decision is to retain it: the shared CLI client does not offer a `firefly`
scope, and Firefly's browser identity mapping remains attached to `profile`.

### Radicale — proxy identity for browsers and DAV clients

At tailnet-restricted `dav.m7.rs`, the outpost accepts browser sessions, OAuth
bearer tokens, and Basic username/app-password credentials. Nginx passes a trusted
principal to Radicale and strips incoming credentials before forwarding.

- Explicit credentials take precedence over cookies. Nginx suppresses header-auth
  session cookies and protects cookie-authenticated writes with Origin checks.
- Authentik controls admission; Radicale enforces collection ownership and native
  mapped sharing. Token/link sharing is disabled.
- A separate read-only Authentik API account supports the sharing UI's directory.
- Outpost caching and stored claims mean per-request `auth_request` is not the
  same as per-request fresh entitlement evaluation.

This is the existing integration closest to a shared HTTP credential gateway.
See [the protocol assessment](mail-auth.md) for its validation limitations.

### Mail — direct Dovecot integration

IMAP and SMTP submission accept Authentik OAuth access tokens or username/app
passwords. Dovecot validates OAuth through userinfo; app passwords use a separate
password-grant provider. Personal mailbox passwords are locked.

The mail mapping checks active status, Mail access, and the explicit mailbox
principal. Authentik does not provision mailboxes or delivery aliases: Nix does.
Service SMTP senders retain independent local credentials. Authentication checks
do not terminate already-established IMAP connections.

### SOGo — delegated client of Mail and DAV

The web interface at `mail.m7.rs` uses its own confidential OIDC client with PKCE
and refresh tokens. Admission requires both Mail and Radicale access. SOGo uses
the user's OAuth access token for IMAP/SMTP and DAV, rather than storing a personal
mailbox password. Our package carries OIDC/backend integration patches.

Logout uses Authentik's end-session endpoint; this is not the same patched
back-channel session model as Grafana or Seerr. SOGo is a client spanning two
resource services, not a third interchangeable API-authentication gateway.

## What the scoped-client change does

The baseline's `mail-and-dav` public client admitted users with either Mail or DAV
access. It used implicit consent, S256 PKCE, a strict loopback callback, five-minute
access tokens, and thirty-day refresh tokens. Mail had a dedicated scope, but DAV
identity was attached to `profile`, alongside generic proxy mappings.

`vksqkonk` replaces it with `gablogin-cli`:

- Explicit consent and dedicated `mail` and `dav` scopes.
- Required `openid` plus at least one service scope, with access to every requested
  service checked during authorization.
- Mandatory S256 PKCE, authorization-code/refresh grants only, the same callback
  and lifetimes, and refresh rotation on every renewal.
- Service-isolated identity mappings instead of generic profile/proxy claims on
  the shared client. Native browser clients remain separate.

Live issuance tests covered login/consent, scope and claim isolation, PKCE,
refresh rotation/replay, narrowing, revocation, and negative authorization cases.
Oama was reauthorized successfully. After removing the premature Firefly scope,
live checks confirmed Mail/DAV issuance and refresh, exact claims, and denial of
Firefly authorization requests. No existing Firefly-bearing shared-client grants
needed revocation. Full mail/DAV/SOGo client acceptance remains incomplete. No
proposed validator or Firefly API-guard patch has been implemented.

## Inconsistencies and concerns

1. **Credentials:** users obtain them in Authentik for Mail/DAV, but in applications
   for most other APIs. Application backend integrations also retain their keys.
2. **Sessions:** applications, outpost sessions, OAuth grants, app passwords, and
   persistent protocol connections have different lifecycles.
3. **Authorization:** roles generally synchronize at login. Group removal is not
   token revocation, and an outpost request is not necessarily a fresh policy check.
4. **Identity:** initial email linking, stable subjects/UUIDs, and explicit resource
   principals coexist. Shared principals need an explicit actor/audit model.
5. **Logout:** configured callbacks are not proof of delivery or equivalent account-
   disable, group-removal, and credential-revocation behaviour. API keys generally
   sit outside browser logout.
6. **Maintenance:** the baseline already includes considerable custom code. Compare
   new designs against the code they would replace, not an imaginary patch-free
   baseline. A universal interface can still conceal many protocol-specific adapters.

Authentik itself also carries fixes for tracking relying-party logins beyond token
expiry and for logout after unrelated unfinished flows. These improve event
handling; they do not create universal revocation guarantees.

The clarified priority is the user-facing connection and credential-management
experience. Different internal token types are not themselves a problem; asking
users to discover another application's PAT-management procedure is the relevant
break in that experience. Predictable access removal and maintenance cost remain
constraints, not reasons to require every service to implement every mechanism.

Keep existing native OIDC and Jellyfin's device flow, the scoped Mail/DAV client,
and Firefly's current browser/API split. Further implementation is not approved
by this assessment. See [the design direction and alternatives](todo/gablogin-api-auth.md)
for the two preferred paths and shared fallback, lifecycle questions, and acceptance
criteria.

## Source map

- [Authentik blueprints and service](../hosts/nixos/alcyone/services/authentik/)
- [Grafana](../hosts/nixos/alcyone/services/grafana/default.nix),
  [Firefly](../hosts/nixos/alcyone/services/firefly.nix),
  [Mail](../hosts/nixos/alcyone/services/mail.nix),
  [Radicale](../hosts/nixos/alcyone/services/radicale.nix),
  [SOGo](../hosts/nixos/alcyone/services/sogo6.nix)
- [Immich](../hosts/nixos/merope/services/immich.nix),
  [Jellyfin](../hosts/nixos/merope/services/media/jellyfin/),
  [Seerr](../hosts/nixos/merope/services/media/jellyseerr.nix),
  [Calibre-Web](../hosts/nixos/merope/services/media/calibre-web.nix)
- [Overlays](../overlays/), [custom packages](../pkgs/), [backup assessment](backups.md)

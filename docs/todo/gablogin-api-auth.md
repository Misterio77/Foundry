# Shared Gablogin API authentication

Status: in progress. Phase 1 (scoped issuance and client configuration) is
implemented in the repository. Consumer hardening, Firefly API authentication,
and deployment/live interoperability tests remain pending.

## Goal

Give authentik-managed services a common authentication contract:

- Browser: login at `auth.m7.rs`, through native OIDC or a trusted proxy session.
- OAuth-capable API clients: authentik-issued access tokens with user-selected
  service scopes, obtained and refreshed by tools such as oama.
- Legacy API clients: authentik username and app password.

All paths converge on the same service entitlement and principal mapping.
Implement Firefly, mail, and DAV first, then extend the contract service by service.
Native OIDC browser login alone does not establish API token support.

Backwards compatibility and preservation of existing sessions are not goals.
Blueprints remain the source of truth; conflicting authentik objects can be
reconciled through its API. Do not preserve legacy authentication paths solely
for migration convenience.

## Existing foundation

- `hosts/nixos/alcyone/services/authentik/gablogin-cli.yaml` defines a shared
  public OAuth client with service scopes, explicit consent, PKCE, rotating
  refresh tokens, and a strict loopback callback; it replaces `mail-and-dav`.
- `home/gabriel/features/productivity/accounts/personal.nix` configures oama's
  `gablogin` entry for that client.
- `overlays/oama-refresh-token-rotation.patch` already fixes upstream oama's
  failure to retain replacement refresh tokens; no new fix is needed for that.
- Mail and DAV already integrate authentik OAuth and app-password paths.
- Firefly browser authentication uses the outpost and trusted CGI identity.
  Its API currently uses Passport, including native personal access tokens.
- Service-specific principal attributes already support mapping separate
  authentik actors to the same backend identity.

See [Gablogin](../authentik.md) and [mail/DAV authentication](../mail-auth.md)
for the existing design. These are starting points, not evidence that the new
contract is implemented.

## Authentication and authorization contract

| Method | Credential | Authorization |
| --- | --- | --- |
| Browser | Authentik login/session | Current service entitlement |
| OAuth API | Gablogin access token | Required service scope and current service entitlement |
| App-password API | Username and authentik app password | Current service entitlement |

Initial service scopes: `firefly`, `mail`, and `dav`. App passwords remain global
credentials; application entitlements still limit which services accept them.
Fine-grained scopes such as `firefly:read` are deferred until adapters enforce
individual API operations.

Required boundaries:

- Reject disabled accounts, expired/revoked credentials, and missing access.
- OAuth scope requests can narrow access, never grant new user permissions.
- Validate the intended issuer/provider and audience/client relationship;
  sharing an issuer or signing key is not sufficient trust.
- Reject ID tokens, refresh tokens, and authentik API tokens as service access
  tokens. Introspection alone must not accidentally admit a refresh token.
- Invalid explicit credentials never fall back to browser-cookie authentication.
- API failures return `401` or `403`, not redirects or login HTML.
- Browser-session API requests retain CSRF protection.
- Client-supplied headers cannot establish trusted identity; backends cannot
  bypass the authentication boundary.
- Keep the authenticated actor distinct from the mapped service principal for
  audit purposes, particularly when automation shares a user's principal.
- Define and test a revocation window. Avoid positive authorization caching
  initially where practical; do not promise immediate revocation without proof.

A shared multi-service access token is an intentional security boundary. Each
consumer must enforce its own scope. Prefer consuming the bearer token at the
trusted authentication layer and passing identity downstream, rather than
exposing a reusable multi-service credential to every backend.

## Phase 1: shared OAuth client and scopes

Replace the `mail-and-dav` client with a public `gablogin-cli` provider/application:

- Authorization code with mandatory S256 PKCE.
- Explicit consent with readable service-scope descriptions.
- Refresh tokens with rotation.
- Existing strict callback: `http://127.0.0.1:8765/callback`.
- Five-minute access tokens, following the existing convention.
- No password or client-credentials grants on this interactive client.

Add scope authorization that requires at least one service scope and access to
**every requested service**, replacing the current mail-or-DAV access check.
Reject unauthorized requests instead of silently implying success.

The authorization policy checks the raw GET `scope` parameter against normalized
`oauth_scopes`, rejecting omission, unknown scopes, repeated parameters, and
normalization differences. It requires `openid` and at least one service scope.
The pinned authorization view exposes both inputs and disables policy-cache reads
for application admission. This avoids authentik's default-to-all and
intersection-with-known-scopes behaviour.

Update oama to request an explicit set, for example:

```yaml
auth_scope: "openid offline_access mail dav firefly"
```

Users can remove services and authorize again for narrower grants. Editing the
configuration does not narrow an existing refresh-token grant. Old grants must
be revoked when their authority should disappear.

Keep native browser OIDC clients separate. The shared client serves user-operated
CLI and non-interactive consumers, not every application's browser login.

Primary files:

- `hosts/nixos/alcyone/services/authentik/gablogin-cli.yaml`
- Service scope mappings and authorization policies under the same directory
- `home/gabriel/features/productivity/accounts/personal.nix`

## Phase 2: reusable credential validation

Inspect the pinned authentik/outpost implementation before selecting an adapter.
Establish whether its existing federation and authentication paths can provide:

- Shared-client OAuth access-token validation.
- Required service-scope enforcement.
- Current service-entitlement checks, not merely claims captured at issuance.
- App-password validation that does not also admit ordinary account passwords.
- Trusted identity output with actor, service principal, and allowed roles.

Prefer extending the existing outpost path. If a patch is necessary, keep
validation close to authentik rather than introduce another credential database
or a service holding broadly privileged authentik API credentials.

Expected credential transport:

- OAuth: `Authorization: Bearer <access-token>`.
- App password: HTTP Basic with authentik username and app password.
- Waterfly: verify that the installed release supports custom headers and can
  supply Basic authentication in place of its normal bearer header. Current
  upstream supports custom headers, but release compatibility and the required
  API-key form field need an actual client test.

Do not reinterpret arbitrary bearer strings as global app passwords. If Waterfly
cannot use Basic as expected, settle an explicit transport before implementing
an alternative.

Validation output should identify the authenticated actor, target service,
mapped principal, authentication method, granted scopes, and service roles.

## Phase 3: Firefly and automation

Patch Firefly's API guard to consume trusted server-side identity from Nginx,
reusing the existing principal/display-name/admin mapping where appropriate.

- Disable native Firefly API-token authentication and issuance, not just its UI.
- Preserve browser API functionality with CSRF protection.
- Keep trusted CGI variables inaccessible to client HTTP headers.
- Ensure credential-bearing API requests cannot fall back to a browser session.
- Ensure separate authentik actors sharing a Firefly principal do not alternate
  that backend user's admin role as they make requests. Define service-account
  role synchronization rather than blindly reuse browser provisioning logic.

Replace the exchange-rate job's PAT with an authentik service account:

- Set `firefly_principal` to the intended existing Firefly identity.
- Grant Firefly access explicitly without unnecessary group membership.
- Authenticate using its own app password.
- Remove the old PAT secret reference; securely provision the replacement
  credential outside this document.

Primary files:

- `overlays/firefly-*.patch`
- `overlays/default.nix`
- `hosts/nixos/alcyone/services/firefly.nix`
- `hosts/nixos/alcyone/services/authentik/firefly.yaml`

## Phase 4: mail and DAV convergence

Tighten existing integrations rather than rebuild them:

- Mail requires the `mail` grant and mapped mailbox identity. Audit current
  userinfo-based validation for issuer/client restrictions and current access
  enforcement.
- DAV requires `dav` for shared OAuth tokens. Generic `ak_proxy` access must not
  serve as a cross-service permission.
- Preserve app-password access only through explicitly configured paths.
- Keep SOGo's browser integration functional, without automatically extending
  shared CLI privileges to its existing tokens.

These consumers exercise three distinct integration types: a PHP API, HTTP DAV,
and IMAP/SMTP. Broader rollout follows only after the common contract works for
all three.

## Verification and acceptance

Use existing upstream test suites through package patches for durable tests.
Temporary integration checks must not become a new ad-hoc repository harness.
Build patched packages natively and evaluate affected Nix configurations.

| Case | Expected |
| --- | --- |
| `firefly` token used for Firefly | Allowed |
| `firefly` token used for mail or DAV | Denied |
| `mail dav` token used for those services | Allowed |
| Missing/unknown scope or unauthorized requested service | Defined fail-closed behaviour |
| Entitlement removed while token remains unexpired | Denied within the defined revocation window |
| Disabled user or service account | Denied |
| Revoked or expired app password | Denied |
| Ordinary account password on app-password-only path | Denied |
| Wrong-provider token, ID token, refresh token, authentik API token | Denied |
| Forged identity headers or direct backend bypass | Denied |
| Invalid explicit credential plus valid browser cookie | Denied |
| Browser API write without valid CSRF protection | Denied |
| Native Firefly PAT | Denied |
| Service account sharing the user's principal | Correct dataset without role mutation |
| Repeated oama renewal across refresh-token rotation | Works |
| Narrower reauthorization | New grant contains only requested scopes |
| Waterfly login, reads, and writes | Work with authentik app password |

Successful `/api/v1/about` authentication is not sufficient Waterfly acceptance.
Test real read/write operations and browser interaction with the patched guard.

## Completion and scope boundaries

Implement in this order:

1. Shared OAuth client and scope policy.
2. Reusable credential validation.
3. Firefly guard and automation account integration.
4. Mail/DAV scope convergence.
5. End-to-end acceptance and clean-break cutover.

Blueprints and code must describe the final intended state. Remove obsolete
providers, grants, and native credentials deliberately; API reconciliation must
converge to blueprints rather than leave invisible configuration. Operational
commands, live credentials, and machine-state migration notes do not belong in
this project document.

Deferred: fine-grained API permissions, automatic OAuth acquisition/refresh in
Waterfly, and adaptation of the remaining authentik-managed services. Each
additional service needs an API/protocol audit; browser SSO is not enough.

## References

- [Authentik OAuth provider, scopes, and scope authorization](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/)
- [Authentik authorization scope handling](https://github.com/goauthentik/authentik/blob/main/authentik/providers/oauth2/views/authorize.py)
- [Authentik token issuance and refresh](https://github.com/goauthentik/authentik/blob/main/authentik/providers/oauth2/views/token.py)
- [Authentik introspection](https://github.com/goauthentik/authentik/blob/main/authentik/providers/oauth2/views/introspection.py)
- [oama authorization and renewal](https://github.com/pdobsan/oama/blob/main/lib/OAMa/Authorization.hs)
- [Waterfly credential handling](https://github.com/dreautall/waterfly-iii/blob/master/lib/auth.dart)

Upstream source references describe investigated behaviour, not necessarily the
pinned package versions. Confirm against pinned sources during implementation.

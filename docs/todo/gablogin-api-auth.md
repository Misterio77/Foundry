# Gablogin: a consistent user-facing authentication experience

Direction: two preferred paths, one shared fallback. Users connect through an
integrated Gablogin login/device-approval flow, or authorize helper-managed OAuth
(such as oama) for tools and unattended use. App passwords created in Gablogin are
the fallback when neither fits. Service-specific mechanisms may remain underneath;
a consistent surface does not require every service to accept every credential type.

Implementation status: retain Firefly's existing browser SSO and native API
credentials as a known exception. The shared OAuth client is limited to Mail/DAV;
scoped issuance is implemented and live-tested, with full client acceptance still
pending. No universal validator, Firefly API-guard patch, or Waterfly OAuth patch
has been implemented. This document supersedes the earlier phased universal rollout
plan; the alternatives below are design context, not an execution queue.

See [the service inventory](../authentik.md) and
[Mail/DAV/SOGo boundaries](../mail-auth.md) for the existing configuration.

## What already exists

At the `5b0316a5` comparison baseline:

- Identity, application admission, and most application-role mappings are central.
- Mail and DAV accept Authentik OAuth tokens and app passwords.
- Firefly and Calibre-Web use proxy browser identity, but Firefly's API remains
  native-token based and Calibre-Web's OPDS/Kobo endpoints are disabled.
- Jellyfin, Immich, Grafana, and Seerr turn OIDC logins into application-owned
  sessions or device tokens. Independent API/service credentials remain.
- Several integrations already carry substantial patches, including session
  revocation and Jellyfin Quick Connect ancestry. “Keep native credentials” does
  not mean “return to an unpatched baseline.”

`vksqkonk` replaces `mail-and-dav` with `gablogin-cli`: explicit consent, Mail/DAV
service scopes, strict scope authorization, PKCE, rotating refresh tokens, and
isolated service identity claims. Firefly's browser mapping remains on `profile`
and is not attached to the CLI client. Issuance and lifecycle tests passed live;
oama reauthorization succeeded. Follow-up tests confirmed that Firefly scope
requests are denied while Mail/DAV issuance and refresh remain functional.
Complete resource-client acceptance is pending.

This is useful standalone work. It neither makes Firefly accept Authentik tokens
nor obliges us to implement a universal authentication layer.

## The clarified user-facing contract

> Users should not need to learn a new credential-management procedure for each
> service. Prefer integrated Gablogin login or helper-managed OAuth; use a centrally
> created app password when neither path fits.

### Preferred path: integrated login or device approval

The user follows the client's login/device-approval path, authenticates through
Gablogin, and approves the connection where required. The client can then use
OAuth tokens, an application session, or a native device token internally.

What matters is that users do not need to discover an application-specific PAT
page, manually generate another credential, and copy it into their client.
Jellyfin's Quick Connect flow fits this model even though the resulting token is
issued by Jellyfin. Native OIDC browser/mobile integrations also fit; they should
not be replaced solely to make their internal credentials look like Mail/DAV's.

“Connect with Gablogin” describes the experience, not a mandate for one literal
button or a particular OAuth grant everywhere. Device approval and native OIDC
can provide that experience while retaining application-managed sessions/tokens.

### Preferred path: OAuth through a helper such as oama

This is a first-class surface for CLI tools, scripts, and unattended jobs that can
consume OAuth access tokens. The user initially authorizes requested service
scopes through Gablogin in a browser. Thereafter the helper stores the grant,
retrieves access tokens for consumers, and manages renewal. Consumers need not
implement a browser callback or refresh-token lifecycle themselves.

Browser authorization and non-interactive use are not opposites. The browser is
used to approve the connection; subsequent requests and refreshes can run without
user interaction. Compared with a static app password, a scoped grant can narrow
service access and use short-lived access tokens without repeated credential
copying. The refresh credential still needs secure storage and lifecycle controls.

Oama does not provide completely headless bootstrap. Expired/revoked grants or
changed scope requirements may need renewed interactive authorization. Credential
storage must be available to the unattended process; token-refresh coordination
and failure/reconnect behaviour need testing. Machine-to-machine OAuth grants are
a separate design, not something enabled by calling a token helper from a cron job.

This path complements integrated login. A client without its own OAuth login UI
may still consume a token command supplied by oama. Conversely, a fixed native-PAT
field does not necessarily accept Authentik access tokens. Both the consumer and
the target service must support the credential contract.

### Shared fallback: create an app password in Gablogin

When neither integrated login nor helper-managed OAuth fits, the user creates a
dedicated app password centrally and supplies it with their Authentik username
using the integration's supported transport. The account password is not the fallback.
App passwords are a deliberate compatibility interface for clients we do not
control, not merely a temporary feature to eliminate from all legacy clients.

This requires real support at both ends. An arbitrary bearer/API-key field cannot
be assumed to accept an app password; Basic authentication, custom headers, or an
adapter must be evaluated against the actual client and server. Never silently
reinterpret arbitrary bearer strings as global app passwords.

App passwords are the fallback for both preferred paths: interactive clients and
non-interactive consumers. They are not only an alternative to browser login, nor
the default just because a program runs unattended.

A service/client only needs the paths relevant to its use. A working integrated
login or helper-managed OAuth path does not require app-password support beside
it. Likewise, an app-password integration does not require adding OAuth to a client
that cannot use it.

### What is and is not being centralized

| Concern | Intended direction | Not implied |
| --- | --- | --- |
| Interactive identity | Gablogin login, MFA and application admission | Identical backend user databases |
| Connecting a client | Integrated login/device approval, helper-managed OAuth, or the shared app-password fallback | Every service accepts every token type |
| Credentials visible to users | Avoid application-specific PAT-generation procedures | Every internal session/device token is issued by Authentik |
| Client lifecycle | Understandable expiry, reconnect and disconnect behaviour | A unified device UI or instant revocation already exists |
| Resource identity | Correct account/data with centrally managed identity mappings | Every backend uses the same username or principal format |
| Automation/backend connections | Explicit credentials and accountable owners | Every operator-managed key must be replaced to satisfy the interactive UX |

Central credential creation, central device management, and central revocation
are related but distinct goals. No unified connected-device dashboard is being
promised by this change. Revocation bounds, logout scope, and existing connection
behaviour still need explicit decisions and tests.

Service scopes narrow a token's authority; they do not grant entitlements. Global
app passwords are not service-scoped because their labels name a device or app.
The preferred paths and fallback offer consistent onboarding, not identical security
properties. Dedicated per-device passwords enable selective credential removal,
but do not alone terminate sessions or connections established with them.

## Current decisions and non-goals

- Keep the scoped Mail/DAV CLI client and finish existing client acceptance.
- Keep native OIDC integrations and Jellyfin's device approval flow. Native tokens
  created behind those flows are not a violation of the intended experience.
- Leave Firefly unchanged for now. Its PAT workflow is a known user-facing
  exception, not proof that all other integrations must be replaced.
- Do not restore a Firefly scope before a consumer actually accepts it.
- Do not build a universal gateway, patch Authentik, or fork a client merely to
  make backend authentication uniform. A specific user-facing gap must justify
  the maintained code and its security boundary.
- Do not treat server-to-server keys, every resource ACL, or every active protocol
  connection as automatically included in a client-onboarding improvement.

These are scope boundaries, not claims that the remaining differences are harmless.
For example, native API credentials may outlive an Authentik login, and shared
principals may complicate attribution. Record and assess those consequences rather
than presenting consistent setup as a universal lifecycle guarantee.

## Firefly and Waterfly: a concrete gap, not the whole architecture

Firefly browser login already fits the vision. Waterfly setup does not: users must
find Firefly's PAT settings and copy a Firefly-issued credential into the client.
The current decision is to tolerate that exception, not to call it implemented SSO.

A preferred browser connection flow would require client support as well as server
support. Waterfly would need appropriate OAuth authorization, callback handling,
and credential storage/renewal. Configuring Authentik or changing Firefly alone
cannot provide that UI. A maintained client fork would be a separate cost.

The app-password fallback might avoid a Waterfly fork if its installed release
can send the required username/password or custom Authorization header. That
compatibility is unverified. It would still require Firefly to accept trusted API
identity and a validated Authentik credential path. Neither change is approved
here; a generic claim that Waterfly supports custom headers is insufficient.

The PTAX job is a separate automation consumer, currently using a Firefly PAT.
Moving it to a service account could be useful, but is not automatically required
by improving Waterfly's user experience. If revisited, retain distinct actor
identity and avoid mutating a shared financial user's admin role per request.

## Earlier architecture alternatives, viewed through this contract

These alternatives describe implementation choices, not competing user visions.
Prefer the smallest change that closes a real user-facing gap. In particular,
option E is stronger than the clarified requirement and is not its definition.

### A. Keep native API credentials behind browser SSO

Selected for Firefly at present: keep its PATs for Waterfly and automation.
Preserve Mail/DAV's existing central-credential paths; do not dismantle them to
make everything equally native.

- Lowest additional implementation cost and closest to the comparison baseline.
- Compatible with application clients and upstream token semantics.
- Credential provisioning/revocation remains distributed. Disabling Authentik
  access does not inherently revoke independent application tokens.
- Existing custom login/logout integrations still need maintenance.

### B. Add a central gate while retaining native API credentials

Put Authentik authentication in front of Firefly's native token validation.
Clients need two credentials, or the gateway stores/injects backend credentials.

- Can centralize admission without replacing the application's API guard.
- Retains application-native credentials and their lifecycle.
- Two client credentials depend on actual client header support; server-side
  injection instead adds sensitive credential storage and principal-to-token mapping.
- Still requires a correct central validation path. It is not a shortcut around
  scope, token-type, cache, or revocation questions.

This may be useful in particular integrations, but risks combining both systems'
complexity without removing the credential-management inconsistency.

### C. Implement centralized credentials for Firefly only

Give Waterfly an Authentik credential and the exchange-rate job a separate
Authentik service account mapped through `firefly_principal`.

- Addresses the immediate browser/API mismatch without promising universal support.
- Requires trusted API identity integration in Firefly and a validated credential
  path. App-password-only support could be an initial stopping point; OAuth need
  not be bundled into the first implementation.
- If selected, the earlier desired clean break was to disable native PAT issuance
  and authentication, not just hide the UI. Browser API CSRF protection must remain.
- Multiple actors sharing a financial principal must not toggle that user's admin
  role on each request. Audit identity and resource identity need separate treatment.
- Waterfly's actual installed-client credential transport and real reads/writes
  must be tested. Custom-header support alone is not acceptance evidence.

This bounds the project and could close Waterfly's manual-PAT gap through the
app-password fallback. Differences elsewhere need evaluation by user workflow,
not elimination merely because the backend credential types differ.

### D. Build a shared HTTP credential boundary

Consolidate the DAV/outpost pattern for compatible HTTP services, potentially via
an outpost patch or a separate gateway. Validate credentials centrally and forward
trusted service identity rather than reusable multi-service tokens.

- Reuses validation, credential precedence, caching policy, and audit conventions.
- Per-service scope, entitlement, principal, and role mappings remain necessary;
  these are different resource semantics, not necessarily arbitrary inconsistency.
- Firefly still needs an API identity adapter. Dovecot still needs its protocol path.
- Adds a critical component or maintained patch. It pays off only if concrete
  consumers reuse it and it replaces enough existing machinery.

A shared policy could be global across managed services while rollout is staged.
That is different from making safe validation an optional per-service mode.

### E. Enforce a universal Gablogin contract

Require managed services to accept browser SSO, scoped OAuth, and app passwords
with consistent identity and lifecycle guarantees across protocols.

- Simplifies the user-facing credential model and potentially access administration.
- Requires adapters wherever applications or clients expect native credentials.
- Does not eliminate application sessions, persistent connections, resource ACLs,
  or service-specific identity mapping; it makes us responsible for reconciling them.
- Expands upgrade/compatibility tests and the impact of Authentik/gateway failures.
- Could justify itself as a deliberate platform project or upstream contribution,
  but is not currently a demonstrated reduction in Foundry's overall complexity.

E increases implementation/maintenance complexity and is not necessary merely to
provide the preferred paths and their shared fallback. The goal permits native
session and device credentials behind central approval. Universal token acceptance would need
an additional justification, rather than following automatically from a desire
for a consistent surface.

## Validator ideas, not an implementation commitment

Inspection found that the existing outpost trusts active introspection responses,
uses cached claims, and can create sessions from header authentication. DAV's
Nginx configuration already prevents cookie fallback and suppresses those cookies
at its public boundary. Do not count those protections as wholly absent.

Two implementation directions were discussed:

- **Core plus outpost changes:** make core introspection enforce resource-specific
  scope/access and fresh identity, then change outpost credential/session handling.
  This has broader maintenance and compatibility implications. Refresh-token
  introspection itself is legitimate; a resource server accepting it is the concern.
- **Potential outpost-only validation:** combine existing introspection (active
  grant and permitted federation) with userinfo (access-token-only validation and
  fresh mappings), then require the target scope and authoritative identity.
  This is a hypothesis to prototype and test, not a proven complete solution or
  proof that current target-service admission policies are automatically rerun.

The embedded outpost here is Rust; patching the older Go proxy implementation
alone would not change the deployed embedded path. No patch for either direction
has been written. The earlier claim that a core patch was necessarily required
was too strong.

## Concerns that survive every architecture

- **Token purpose:** access, refresh, ID, Authentik API, and application-native tokens
  are not interchangeable. Verify intended provider/client relationships and scopes.
- **Freshness:** issuance-time authorization, token refresh, request validation, and
  session revocation are separate checks. A five-minute access-token lifetime is
  not a five-minute bound on every derived session or open connection.
- **Caching:** define a measured revocation bound. Removing all positive caches
  increases network/database work; repeated app-password exchanges also mint tokens
  and generate authentication events. Zero caching is not an adopted requirement.
- **Credential precedence:** invalid explicit credentials must not authenticate via
  unrelated browser cookies. Browser API requests still need CSRF protection.
- **Actor versus principal:** shared backend identities must not erase attribution
  or produce conflicting role synchronization.
- **Failure behaviour:** distinguish API 401/403 from browser redirects, fail closed
  on missing authoritative identity, and protect direct backend access.
- **Independent credentials:** browser logout does not inherently revoke OAuth
  grants, app passwords, native API keys, or application backend integration keys.
- **Evidence:** configured back-channel URLs, passing builds, or successful callbacks
  do not prove authenticated requests are rejected or independent sessions survive.

## Acceptance: evaluate the user workflow and the security boundary

A successful token exchange is necessary for an OAuth integration, not sufficient
proof of a usable connection flow. For a selected service/client pair, establish:

1. **Connect:** where the user starts, how browser return/device approval or helper
   authorization works, how tools retrieve tokens, or where the centrally created
   app password is entered. No hidden step
   should require generating an application PAT unless it is a declared exception.
2. **Use:** real reads/writes against the right user's resources, not just an
   authenticated version/about endpoint. Include native/mobile behaviour where used.
3. **Renew/reconnect:** expiry, restart, refresh rotation, revoked credentials, and
   understandable recovery without exposing raw token-management details to users.
   For helper-managed OAuth, test unattended credential-store access, concurrent
   consumers, and the point where a fresh interactive authorization becomes necessary.
4. **Disconnect:** what removing that credential/connection actually stops, within
   what bound, and what remains active. Test independent devices and sessions.
5. **Authorize:** denied access, disabled accounts, changed entitlements, wrong
   token purpose/provider/scope, forged identity, and explicit credentials alongside
   cookies. Consistent UX must not weaken service boundaries or browser CSRF checks.
6. **Maintain:** client-version constraints, upstream support, patches required,
   outage behaviour, and the existing special cases the change would actually remove.

Do not imply that logout, device disconnection, app-password deletion, OAuth-grant
revocation, and account disable are interchangeable operations. A consistent surface
needs honest descriptions of those effects, not a misleading single label.

## Remaining decisions and next evaluation

The user-facing goal and acceptance of internal native tokens are settled. The
remaining questions concern how far to implement that goal and at what cost:

- Which actual client workflow should be improved after Mail/DAV/SOGo acceptance?
  What specific user action or credential-management detour would disappear?
- Does that client support integrated login, helper-supplied OAuth tokens, or
  app-password transport? Would supporting it require a fork or an upstream change?
- What credential breadth and expiry are acceptable for the global app-password
  fallback, given that it is not equivalent to a service-scoped OAuth grant?
- Where should users inspect/disconnect connections, and which current controls
  suffice before considering any new central interface?
- What revocation bound is acceptable for new requests versus existing sessions
  and connections? What must remain independent when one device is disconnected?
- Can a shared adapter replace concrete duplicated code, or would it add another
  layer without removing existing application integrations?

The immediate follow-up proposed is acceptance of the existing Mail/DAV/SOGo
clients. No new authentication implementation or universal rollout is selected.
Durable tests should extend existing upstream/package suites; exploratory checks
belong outside the repo.

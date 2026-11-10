# Gablogin authentication: directions under evaluation

Status: retain Firefly's existing browser SSO and native API credentials. The shared
OAuth client is limited to Mail/DAV; the premature Firefly scope has been removed.
Scoped issuance is implemented and live-tested. No universal validator or Firefly
API-guard patch has been written. Broader consistency goals remain under evaluation;
this document replaces the previous phased implementation plan.

The concern driving the reassessment is inconsistency between services and what
“managed by Gablogin” actually means. Before choosing more machinery, distinguish
credential-management friction, access-removal behaviour, and maintenance cost.

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

## Separate the goals

1. **Central identity:** one account, login, MFA, and application-admission model.
   Largely present already.
2. **Central credentials:** clients obtain and revoke credentials in Authentik,
   rather than each application's API-token UI. Present for Mail/DAV, not universal.
3. **Predictable revocation:** defined behaviour when a credential, entitlement,
   account, or login session is revoked. These are different events and lifecycles.
4. **Consistent integration:** fewer service-specific rules and patches. A uniform
   user interface does not necessarily reduce the underlying adapter count.

Service scopes narrow a token's authority; they do not grant entitlements. Global
app passwords are not service-scoped simply because their labels name a device
or application. Separately issued credentials can still belong to one centrally
approved identity, as Jellyfin's device-token lineage demonstrates.

## Alternatives

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

This bounds the project, but intentionally leaves differences elsewhere.

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

The assessment so far is that E increases implementation/maintenance complexity
while reducing user-facing inconsistency. Its net value remains a user decision,
not a consequence of the contract looking cleaner on paper.

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

## Questions for the next evaluation

- Which inconsistency is most costly: where credentials are obtained, what access
  removal means, or how much bespoke code is maintained?
- Is a centrally approved native device credential acceptable when its ancestry
  and revocation are tracked, as in Jellyfin?
- What revocation bound is acceptable for new requests, and what should happen to
  existing sessions/connections?
- Which services genuinely need all credential types rather than only the methods
  their clients use?
- Which existing patches or special cases would a shared design actually remove?

Beyond retaining Firefly as-is and limiting the CLI client to Mail/DAV, no further
implementation order is selected. Evaluate the existing services against these
questions before reviving the previous universal rollout plan. Durable tests should
extend existing upstream/package suites; exploratory checks belong outside the repo.

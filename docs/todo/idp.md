# Identity provider and device credentials

Planning notes from a read-only review of Foundry and Authentik documentation
on 2026-11-03. This is a proposal, not a deployment record or proof of client
compatibility. No live hosts were inspected. Version references describe the
sources reviewed and must be rechecked before implementation.

This document intentionally contains no credentials, device identifiers,
recovery material, or private notification destinations. Keep those out of
this public repository; use SOPS for deployment secrets and maintain recovery
material separately.

## Goals and security model

- Use a YubiKey/FIDO2 credential to authorize devices and interactive access.
- Allow routine mail and calendar synchronization without the key plugged in.
- Replace a shared password with independently revocable device credentials.
- Show active authorizations, their creation time, and meaningful last activity.
- Notify a phone when a new authorization or security-sensitive change occurs.
- Introduce SSO for suitable services without forcing every protocol through a
  browser login page.

Unplugging a hardware key prevents new decryptions, but does not retract a
password already handed to a client or terminate an authenticated connection.
A refresh token is also a stealable bearer credential. Its advantages are
independent revocation, expiration, observability, and potentially narrower
permissions, not immunity to malware. Revocation cannot remove downloaded
mail or other data already copied to a device.

Keep network access, interactive identity, device authorization, and local
secret storage as separate layers. Retain the existing tailnet boundary.

## Existing Foundry integration points

| Area | Declared configuration | Planning consequence |
|------|------------------------|----------------------|
| Mail | Simple NixOS Mailserver on Alcyone; Dovecot evaluated to 2.4.5 | Keep the mail stack and investigate OAuth authentication. |
| Mailbox identity | Declarative personal mailbox, aliases/catchalls, and separate service senders | Preserve storage paths, delivery mappings, and sender restrictions. |
| Desktop clients | mbsync, msmtp, aerc; oama already handles other accounts | Reuse the existing OAuth client pattern where compatible. |
| Calendar | Radicale with htpasswd; personal DAV credentials use the same pass entry as mail | Separate calendar credentials as part of the migration. |
| Background synchronization | Both mbsync and vdirsyncer have a GPG-unlocked ExecCondition | Authentication changes alone will not remove the hardware-key dependency. |
| Network | IMAP/submission and most private web services are tailnet-only | Do not replace network isolation with SSO. |
| Hosting | Alcyone already runs nginx, ACME, PostgreSQL, SOPS, and persistence | Natural first placement, subject to a capacity check. |
| Backups | Alcyone's Borg job selects application paths but excludes PostgreSQL | Add consistent identity-database backups before relying on the IdP. |
| Notifications | Grafana has email alerting; no ntfy/Gotify deployment was found | Phone push needs a transport or additional service. |

Relevant files:

- `hosts/nixos/alcyone/services/{default,mail,radicale,headscale}.nix`
- `hosts/nixos/alcyone/services/{backups-jobs,prometheus}.nix`
- `hosts/nixos/alcyone/services/grafana/default.nix`
- `hosts/nixos/common/optional/{nginx,postgres}.nix`
- `home/gabriel/features/productivity/{mail,calendar,oama}.nix`
- `home/gabriel/features/productivity/accounts/{personal,mgc,usp}.nix`
- `modules/home-manager/oama.nix`
- `docs/todo/backups.md`

## Candidate: Authentik

Authentik provides WebAuthn/FIDO2 authentication, OAuth/OIDC, refresh tokens,
LDAP compatibility, app passwords, event rules and webhooks, user self-service,
and configuration-as-code through Blueprints. The initial design does not
require enterprise endpoint-management features.

Three important limitations need explicit acceptance tests:

1. **Browser sessions are not device authorizations.** OAuth refresh tokens
   deliberately survive termination of the originating Authentik browser
   session. This is documented and reflected in the reviewed 2026.8.5 token
   model. Deleting a browser session must not be presented as a mail-device
   kill switch.
2. **App-password names are labels, not application scopes.** Authentik app
   passwords can authenticate their owner wherever app-password authentication
   is enabled. A password labelled for mail is not automatically restricted to
   mail. Application access policies still apply to the user, but do not by
   themselves give each app password a distinct scope.
3. **Identity activity is not mailbox activity.** Login, token refresh, LDAP
   authentication, and an established IMAP connection are different events.
   A unified device-labelled dashboard is a target to validate, not a promised
   out-of-the-box capability.

## Proposed topology

```text
YubiKey / FIDO2
       |
       v
Authentik on Alcyone, behind nginx
       |
       +-- native OIDC --> selected web applications
       +-- OAuth tokens --> Dovecot --> existing mailboxes
       +-- event webhook --> authenticated push transport --> phone
       +-- optional LDAP outpost <-- password-only clients via Dovecot

Mail delivery, service senders, SSH recovery, SOPS, and deployment signing
remain independent of interactive Authentik login.
```

### Placement and exposure

Use a stable hostname, tentatively `auth.m7.rs`, with ACME and backend listeners
restricted to loopback. Start tailnet-only, following existing nginx allowlist
conventions. The Headscale extra-record generator recognizes restricted vhosts
and maps them to tailnet addresses; verify the new vhost is discovered.

Check Alcyone's actual resources before choosing placement definitively.
Upstream's small Docker Compose deployment guide calls for a host with at least
two CPU cores and 2 GB RAM; that is guidance, not a measurement of this host.

If Headscale enrollment later uses Authentik, resolve the bootstrap dependency
first: an unenrolled device cannot reach a tailnet-only IdP. Options include
public HTTPS for the IdP or a deliberate alternative enrollment path. Existing
network, SSH, and administrative recovery paths must remain usable during IdP
failure.

Trust forwarded headers only from the actual reverse proxy, overwrite
client-controlled identity headers, and support the required WebSocket paths.
Do not expose backend, LDAP, or metrics listeners publicly. If adding nginx
forward-auth later, use current integration instructions and patched releases,
not old copied snippets.

### NixOS deployment

The reviewed Foundry nixpkgs pin packages Authentik 2026.5.6, but no corresponding
server module was found there. The community `nix-community/authentik-nix` flake
provides the NixOS module, server/worker, tests, and optional outposts; its
reviewed main branch targets 2026.8.5.

Evaluate that flake first. It is community packaging, not an officially
supported upstream deployment method. Its README warns that overriding its
nixpkgs can break Python dependencies, so do not automatically make every input
follow Foundry's nixpkgs. Review current security advisories when choosing the
actual pin.

Alcyone currently evaluates to PostgreSQL 14.24. Do not let importing an IdP
module silently change the existing PostgreSQL major version. Treat any
upgrade as a separate, database-aware migration.

Proposed configuration locations:

- `flake.nix` / `flake.lock`: pinned deployment module input.
- `hosts/nixos/alcyone/services/authentik.nix`: service, nginx, runtime secret
  references, persistence, and monitoring integration.
- An adjacent `authentik/` directory if flows and application Blueprints warrant
  separate files.
- Existing service modules: application-specific OIDC settings, added one at a
  time rather than through a blanket reverse-proxy gate.
- Existing backup and monitoring modules: database dumps and health checks.

### State, secrets, and recovery

Use a dedicated PostgreSQL database/user and explicit persistence for mutable
Authentik files. Inspect the chosen module's StateDirectory/DynamicUser layout
before defining impermanence mounts; do not assume container paths apply.

Supply the Authentik secret key, SMTP credentials, OAuth client secrets,
outpost tokens, and push credentials at runtime through SOPS. Blueprints can
reference runtime environment variables or files. Never interpolate plaintext
secrets into Nix-generated store files.

Back up the PostgreSQL database using PostgreSQL-native tooling and include the
dumps in the off-host backup set. Also preserve required mutable files and
secret-key/recovery material through appropriate independent mechanisms.
Blueprints do not replace the database: enrolled authenticators and runtime
state are not reconstructed merely by redeploying Nix.

Restore-test before making Authentik authoritative. Recovery must not depend
solely on the mailbox or IdP being recovered. Document operational recovery
procedures separately without committing recovery credentials.

## Authentication and authorization policy

- Start with the existing human identity and an explicit canonical mailbox
  claim. Do not assume the Authentik username equals the mailbox address.
- Require YubiKey/FIDO2 for interactive authentication. Enroll a second hardware
  key if available and establish an independent recovery mechanism.
- Disable public self-registration and add explicit application access
  bindings. Avoid accidental access for every user.
- Separate ordinary application use from IdP superuser administration. Broadly
  reusable app passwords are particularly undesirable on an administrator.
- Require fresh authentication for granting long-lived access and changing
  credentials. An old SSO cookie plus a consent screen is not proof of recent
  hardware-key use.
- Initially test access-token lifetimes around 5–15 minutes and longer-lived
  refresh tokens, with rotation where supported. Choose final lifetimes based
  on compatibility, revocation tests, and acceptable re-enrollment frequency.
- Use strict redirect URI allowlists and explicit audience, scope, and mailbox
  mappings. Tokens intended for unrelated applications must not authenticate
  to mail.

### Desktop token storage

The current oama configuration encrypts credentials to the GPG identity.
Keeping personal-mail refresh tokens behind the same hardware-key decryption
would retain the unwanted dependency.

Investigate a locally available secret-storage backend, such as a
login-unlocked Secret Service keyring, protected by the device's local security.
Use the hardware key to authorize access rather than decrypt every token read.
Confirm support in the packaged oama version, persistence, and behavior from
systemd user services, including headless and locked-session behavior.

Adjust the GPG ExecCondition gates carefully. The synchronization services also
handle other accounts; do not remove protection or break authentication for
those accounts incidentally. Splitting jobs by credential-availability policy
may be preferable to changing a global gate.

## Mail integration

Keep mailbox existence, aliases, local delivery, and service-sender accounts in
Foundry. Use Authentik to authenticate human clients rather than moving all mail
account provisioning into the IdP.

The intended result is that incoming delivery does not depend on interactive
identity availability. Dedicated SMTP credentials for application senders can
remain independent. Preserve submission-only authentication and existing sender
restrictions; do not enable authentication on the public delivery listener.

### OAuth-capable clients

Prototype this path with a disposable mailbox:

```text
oama obtains/refreshes tokens from Authentik
  -> mbsync / msmtp presents an access token
  -> Dovecot validates it and resolves the existing mailbox
```

oama supports custom providers, and the existing Google account definitions
show the client-side pattern. Dovecot supports OAuth bearer authentication.
Confirm the details against Dovecot 2.4 and the actual packaged clients.

Investigate online token introspection first because revocation is a priority.
Offline JWT verification can continue accepting an issued token until expiry.
Introspection still requires testing authentication caches, failure behavior,
and established connections: validation at login is not continuous
reauthorization of an open IMAP session.

Test SMTP separately through Postfix's Dovecot SASL integration. Successful
IMAP authentication alone does not prove submission compatibility.

### Password-only clients

An optional Authentik LDAP outpost can accept app passwords through an
appropriate bind flow. This provides independent credential revocation without
requiring arbitrary-provider OAuth support in every client.

Do not simply enable `mailserver.ldap` as a drop-in change. The pinned mailserver
module gives LDAP users UUID-based homes under a different storage layout from
existing declarative accounts. Investigate an authentication-only LDAP passdb
while retaining declarative userdb and delivery mappings. Verify ordering,
canonical usernames, fallback behavior, and that no empty replacement mailbox
is selected accidentally.

Use authentication binds rather than expecting Authentik to expose reusable
password hashes. Keep the LDAP service identity least-privileged. Review
app-password acceptance and MFA policy explicitly: app passwords satisfy the
password stage, not arbitrary additional MFA stages.

Prefer direct LDAP binds, or define and measure a short cache lifetime.
Authentik warns that cached binds are not invalidated by session revocation or
credential changes. Dovecot-side caching must also be accounted for.

Remember the app-password scope limitation: independent revocation does not
mean each credential is restricted to a named service. Keep this compatibility
path narrow and test which other endpoints could accept the same credential.

## Other service integrations

Prefer native OIDC over browser forward-auth when available. External login
does not necessarily revoke application-local sessions, API tokens, or native
client credentials; test logout semantics per application.

| Service | Candidate approach | Order / constraints |
|---------|--------------------|---------------------|
| Grafana | Native OAuth/OIDC | First low-risk real integration; retain local recovery login initially and map roles explicitly. Decide separately whether anonymous tailnet viewing should remain. |
| Immich | Native OAuth, including the mobile callback | Link existing accounts carefully; validate installed-version logout support. Preserve intentionally public sharing routes. |
| Mail | OAuth plus optional LDAP app-password fallback | Early disposable prototype; migrate real devices only after lifecycle tests. |
| Radicale | Investigate DAV-compatible authentication | Separate calendar credentials from mail. A browser redirect in front of DAV is not a solution. Preserve existing collection ownership and paths. |
| Headscale | Native OIDC for enrollment | Later, after bootstrap and independent recovery are resolved. IdP logout does not automatically remove a tailnet node. |
| FreshRSS | Investigate web SSO separately from client API access | The API is enabled; do not redirect native clients to browser login. |
| Firefly | Investigate trusted-header authentication | Preserve PAT-based automation and intentional route access; validate the installed version. |
| Jellyfin / Calibre | Client compatibility first | Do not break TVs, native apps, OPDS, or service-to-service access. Not initial scope. |
| Nixbot / Prometheus | Optional protection for interactive browser use | Preserve build/auto-upgrade APIs and metrics scraping. Do not blanket-gate these vhosts. |

## Notifications and visibility

Use Authentik event rules and an authenticated generic webhook to ntfy or
another phone-push transport. No push service or destination is selected yet.
Do not include tokens, passwords, recovery links, or other credential material
in notification payloads.

Initial events to investigate:

- Interactive login.
- New OAuth authorization, distinct from routine refreshes.
- App-password creation.
- MFA enrollment/removal.
- Recovery activity and relevant administrative changes.

Start by notifying on all interactive logins rather than relying exclusively on
unknown-device heuristics. Authentik can classify a login as known when another
session exists from the same IP; a shared NAT or tailnet path is not strong
device identity. A new OAuth authorization can also use an existing browser
session without generating a new interactive login, so test both event paths.

The desired dashboard should distinguish:

- Authentik browser sessions.
- OAuth authorizations/refresh credentials.
- LDAP app passwords.
- Application-local sessions and active mail connections.

Validate device naming, creation timestamps, last-use meaning, and what each
revoke operation actually affects. Add custom aggregation only if the native
interface proves insufficient; do not begin by building another identity UI.

Add internal health/metrics checks and backup-age alerts to existing monitoring.
Do not depend exclusively on the affected mail system for critical identity or
backup failure notifications.

## Configuration as code and rollback

Use version-controlled Blueprints for applications, mappings, flows, policies,
and notification rules. Keep enrolled hardware credentials and runtime grants
as protected database state. Establish explicit dependencies between Blueprints
rather than assuming discovery order.

Blueprint application is transactional, but removing a Blueprint file does not
delete the objects it created. Treat removals as deliberate migrations. A Nix
generation rollback also does not undo applied Blueprints or database schema
migrations. Define database-aware backup/restore and rollback procedures before
upgrades.

Avoid a large generic SSO abstraction initially. Implement one working native
OIDC integration and one working mail lifecycle before extracting shared Nix
helpers.

## Rollout and acceptance tests

### Phase 1: standalone identity service

- [ ] Confirm Alcyone capacity and select a supported, patched deployment pin.
- [ ] Deploy behind nginx without changing existing service authentication.
- [ ] Configure hardware-key login, explicit access policies, and recovery.
- [ ] Add persistence, PostgreSQL dumps, off-host backup, and monitoring.
- [ ] Select and test an authenticated phone-notification transport.
- [ ] Restore the IdP and recover administrative access without relying on it.

### Phase 2: one real application

- [ ] Integrate Grafana using native OAuth/OIDC.
- [ ] Verify account linking, role mapping, expiry, logout, and IdP downtime.
- [ ] Retain local recovery access until the new path is proven.

### Phase 3: disposable mail lifecycle

- [ ] Authorize a test client through fresh YubiKey authentication.
- [ ] Sync and submit mail with the key unplugged.
- [ ] Identify the authorization and its activity in Authentik.
- [ ] Receive a new-authorization notification, including when SSO is reused.
- [ ] Revoke the correct credential, not merely its browser session.
- [ ] Measure refresh failure, new-login rejection, and existing connections.
- [ ] Verify another device remains unaffected.
- [ ] Verify unrelated-app tokens cannot authenticate to mail.
- [ ] Test password-only credentials, scope limitations, and cache behavior.
- [ ] Confirm mailbox paths, aliases, delivery, and sender restrictions survive.
- [ ] Confirm delivery remains available during IdP failure.

This phase decides whether Authentik meets the device-management requirement.
Do not migrate all clients based only on successful browser login.

### Phase 4: personal clients and calendar

- [ ] Inventory phone and other native clients, including custom-provider OAuth
  support, background sync, and local token storage.
- [ ] Migrate one device at a time with a tested rollback path.
- [ ] Separate DAV credentials from mail even if DAV initially stays
  password-based.
- [ ] Revisit GPG synchronization gates without disrupting other accounts.
- [ ] Retire the shared credential only after all consumers are accounted for.

### Phase 5: broader SSO

- [ ] Integrate Immich, then selected web services with native support.
- [ ] Consider Headscale only after enrollment bootstrap and recovery tests.
- [ ] Document per-service session revocation and remaining local credentials.

## Outstanding decisions

- Actual phone/mail/DAV client inventory and arbitrary-provider OAuth support.
- Stable IdP hostname and tailnet-only versus eventual public exposure.
- Hardware-key availability and independent recovery arrangement.
- Push transport, its availability outside the tailnet, and notification policy.
- Acceptable token lifetimes and revocation delay for existing connections.
- Whether Authentik's native token/session interface is sufficient or needs
  supplementary device-oriented visibility.

Do not commit private answers such as recovery material, notification secrets,
or device identifiers here.

## References

- [Authentik user interface, sessions, and app passwords](https://docs.goauthentik.io/users-sources/user/user-interface/)
- [WebAuthn/FIDO2 setup](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/authenticator_webauthn/)
- [User login stage and session behavior](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/user_login/)
- [OAuth/OIDC provider](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/)
- [Front-channel and back-channel logout](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/frontchannel_and_backchannel_logout/)
- [LDAP provider, app-password binds, and caching](https://docs.goauthentik.io/add-secure-apps/providers/ldap/)
- [Notification rules](https://docs.goauthentik.io/sys-mgmt/events/notifications/)
- [Webhook transports](https://docs.goauthentik.io/sys-mgmt/events/transports/)
- [Notification policy examples](https://docs.goauthentik.io/sys-mgmt/events/notification_rule_expression_policies/)
- [Blueprints](https://docs.goauthentik.io/customize/blueprints/)
- [Blueprint runtime-secret tags](https://docs.goauthentik.io/customize/blueprints/v1/tags/)
- [Backup and restore](https://docs.goauthentik.io/sys-mgmt/ops/backup-restore/)
- [Reverse proxy requirements](https://docs.goauthentik.io/install-config/reverse-proxy/)
- [Security advisories](https://docs.goauthentik.io/security/)
- [Community Authentik NixOS deployment](https://github.com/nix-community/authentik-nix)
- [Dovecot OAuth authentication](https://doc.dovecot.org/latest/core/config/auth/databases/oauth2.html)
- [oama and custom providers](https://github.com/pdobsan/oama)
- [Grafana integration](https://integrations.goauthentik.io/monitoring/grafana/)
- [Immich integration](https://integrations.goauthentik.io/media/immich/)
- [Headscale integration](https://integrations.goauthentik.io/networking/headscale/)
- [Reviewed Authentik OAuth token model](https://github.com/goauthentik/authentik/blob/version/2026.8.5/authentik/providers/oauth2/models.py)

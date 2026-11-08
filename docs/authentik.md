# Gablogin / Authentik

Describes the checked-in configuration, not deployment status. Sources:
[Authentik](../hosts/nixos/alcyone/services/authentik/),
[Jellyfin](../hosts/nixos/merope/services/media/jellyfin/),
[Immich](../hosts/nixos/merope/services/immich.nix),
[Grafana](../hosts/nixos/alcyone/services/grafana/default.nix),
[Seerr](../hosts/nixos/merope/services/media/jellyseerr.nix).

## Access

- `auth.m7.rs` is public, including the admin UI; authentication, MFA and
  permissions protect administration, not a separate network ACL. Backend
  listeners are loopback-only; HTTPS metrics require a dedicated client
  certificate, not a tailnet source address. See [metrics mTLS](metrics-mtls.md).
- MFA is optional; accounts with an enrolled WebAuthn **or TOTP** device must
  validate it. WebAuthn requires user verification but not hardware-key attestation.
  Sessions persist for 30 days. Branding/default locale is Gablogin/`pt-BR`;
  saved user preferences can override the locale.
- Password changes, profile/email settings and authenticator enrollment require
  the current account password (not an app password), then enrolled MFA if any.
  A retained browser session alone is insufficient. Adding a missing email during
  application authorization has the same checks; ordinary authorization with an
  existing email does not prompt again. These are flow-level checks; Authentik's
  separate authenticator deletion API does not gain a fresh-authentication check.
- Password flows deny entry at reputation scores of -5 per username or -20 per
  client IP. Failed identification/password attempts lower scores; successful
  logins raise them. Scores expire after 15 minutes and survive flow restarts.
  Checks run after login identification and before sensitive-change passwords,
  including direct flow URLs. This is a temporary cooldown, not account
  deactivation; existing-email app authorization and email recovery remain usable.
- Email password recovery expires after 15 minutes and allows five attempts per
  account per 15 minutes. It neither removes MFA nor reactivates disabled users.
  After email verification, enrolled MFA is checked before prompting for or
  writing a new password; successful recovery then creates a login session.
  Email uses `auth@m7.rs` through tailnet-restricted SMTP at `mail.m7.rs:465`.

Groups describe access tiers; application entitlements carry the permissions.
Each tier is complete on its own, without requiring membership in lower tiers.

| Group | Application entitlements | Authentik administration |
| --- | --- | --- |
| `user` | `access` on Grafana, Immich, Jellyfin and Seerr | None |
| `trusted` | `access` on all six services, including Mail and Radicale | None |
| `admin` | `access` on all services; `admin` on Grafana, Immich, Jellyfin and Seerr | None |
| `authentik-admin` | None | Native Authentik superuser |

`authorization.yaml` defines the groups and the common access policy. Each
service blueprint defines its own entitlements and group bindings. Application
admission checks active status and the application's `access` entitlement;
role mappings check entitlements rather than group names or user overrides.
An `admin` entitlement alone does not replace `access`; the `admin` group grants
both. Authentik superuser status is intentionally independent of app access.

The application mappings translate `admin` into Jellyfin's `jellyfin-admins`,
Immich's `admin`, Grafana's `GrafanaAdmin` (server administration), and Seerr's
`ADMIN`. Ordinary access maps to `jellyfin-users`, `user`, `Viewer`, and `REQUEST`,
respectively. These are downstream claims, not Authentik RBAC roles.

Memberships are live identity data, not blueprint-managed users: `gabriel` belongs
to `trusted`; `akadmin` belongs to `admin` and `authentik-admin`; other human users
belong to `user`. Service identities are managed separately. App-role changes
take effect according to each application's login/session behavior, not instantly
when an entitlement changes.

Mail and Radicale each have their own `access` entitlement and resource principal,
while the shared OAuth client admits access to either service. See
[mail authentication](mail-auth.md). Blueprints describe final state; one-time
cleanup of superseded database objects belongs in an API migration, not deletion
entries retained in the blueprints.

## Application behavior

Avatars use the self-hosted Robohash service at
`https://avatars.m7.rs/%(username)s.png` in Gablogin and the OIDC `picture` claim.
nginx fixes generation to kittens (`set4`), 200×200 pixels, disables remote
Gravatar lookups and caches successful images. Usernames select the image; there
is no editable avatar-seed field. Authentik caches avatar lookups by resolved URL;
local initials remain its outage fallback, but aren't shared over OIDC.

Immich replaces the profile image on each OAuth login, including existing images,
and deletes the old file after a successful replacement. A failed fetch or decode
leaves the old image intact. Jellyfin and Seerr also refresh existing users'
avatars from the picture claim, retaining the old image if it's absent. Grafana's
OIDC-picture patch stores a valid HTTPS picture URL on login and otherwise falls
back to its existing Gravatar/default-image behavior. Picture changes reach these
applications on the next OAuth login, not immediately in existing sessions.

**Jellyfin:** admits either role, manages all-library access and admin status,
allows audio transcoding and disables video transcoding for everyone. New
accounts can be created; automatic username migration and email linking are off.
Existing subject-to-user bindings remain authoritative. The startup guard
rejects local authentication providers and missing/conflicting identity maps.
Gablogin pictures sync on OAuth login, replacing existing Jellyfin profile images;
missing pictures leave the existing image alone.

The web client uses same-tab Gablogin, hides password controls, and returns to
login on authenticated 401s. Explicit logout clears local state first. Browser
logins marked by the OIDC callback then open Authentik's application logout page;
Quick Connect logins (and browser logins predating that marker) finish locally.
A marker is bound to the bearer hash, so a later Quick Connect login does not
inherit an earlier OIDC login's logout behavior. Native clients use Quick Connect:
`https://media.m7.rs/connect`, optionally `?user_code=012345`. QR codes carry only
the public six-digit code; approval remains explicit and the tab can then close.
The approval form validates six ASCII digits, decodes API error strings, and offers
a new OIDC sign-in when its authorization expires or is revoked.

The patched plugin records each Jellyfin token's root OIDC identity, including
Quick Connect approvals made from the native menu or `/connect`. Devices approved
by a Quick Connect device inherit the same root. A delivered session-scoped
back-channel logout revokes that root and its descendants, not independent
logins. Token hashes, identity metadata and logout markers are persisted in
`plugins/configurations/Jellyfin.Plugin.OIDC.SessionLineage.json` (mode `0600`);
raw bearer tokens are not stored. Session inactivity does not remove lineage;
cleanup verifies that the token itself is gone. Failed deletions retain their
records and return an error so Authentik can retry, including partial failures.

Logout markers cover authorizations started before the logout, not a permanent
ban on the OIDC session ID: Authentik can reuse that ID after application-only
logout. A fresh OIDC flow can sign in again, but old tokens, Quick Connect
approvals and in-flight pre-logout flows stay revoked. Retries retain the original
cutoff; a distinct later logout revokes the new authorization too. Existing
lineage files remain compatible and must not be cleared to recover from a 401.

For the initial lineage rollout, revoke pre-existing Jellyfin devices explicitly
and sign in again with OIDC before approving new devices. Old approval ancestry
cannot be reconstructed; untracked sessions cannot approve more devices. There
is no longer a restart fallback that logs out the entire account. A missing
lineage match logs a migration warning instead. Corrupt state stops startup;
failed writes reject the login/approval rather than issuing an untracked token.
The tracking cap rejects new logins rather than evicting live revocation data.
Verify the three-session revocation case, a chained approval, an independent
OIDC login, app-only logout/relogin with the same Gablogin session, a Jellyfin
restart and an aged Authentik session after deployment.

**Immich:** OAuth-only, auto-launch and auto-registration enabled. Existing
accounts can link by matching email on first OAuth login: verify the intended
email/identity before admission. Admin status syncs from `immich_role`; quota
syncs from the user's `immich_quota` attribute (GiB, default 8; -1 unlimited).
Browser/mobile access is public with native shared links; the separate public-share
proxy has been removed.

**Grafana:** OAuth-only with strict role mapping and no email-based linking.
The `admin` entitlement grants server administration; ordinary access is Viewer.
Basic/local login and anonymous viewing are disabled.
Generic OAuth back-channel logout is enabled with the explicit issuer
`https://auth.m7.rs/application/o/grafana/`, its HTTPS `jwks/` endpoint and signed
ID-token validation. Authentik sends signed events to
`https://dash.m7.rs/login/generic_oauth/backchannel-logout`. OAuth refresh is
disabled and `offline_access` is not requested: local sessions do not depend on
access-token expiry or IdP availability. Grafana's own maximum/inactive session
lifetimes still apply. User-initiated logout retains Authentik's Grafana
end-session redirect.

Verified issuer/client/subject, optional `sid` and ID-token issuance time are
bound to each new local session. Delivered `sid` events revoke matching sessions
(and match `sub` too when supplied); subject-only events revoke all that subject's
sessions for this client. Monotonic database cutoffs are checked on session
creation and authenticated session lookups. Repeated/out-of-order delivery cannot
undo revocation; cookie rotation and OAuth-token updates do not replace the
original binding. Old ID tokens cannot establish usable sessions after logout.
A fresh login with an ID-token `iat` later than the logout can succeed even with
a reused `sid`; same-second login/logout requires retrying in the next second.
Already-running requests, WebSockets and rendered pages are not terminated.
Service accounts/API keys are not covered by browser-session logout. Signing keys
are fetched only from the configured HTTPS URL, cached for an hour and refreshed
on verification failure with five-second backoff. Invalid events return 400;
key-fetch/storage failures return 503. Successful delivery means the cutoff was
persisted, not that an already-running request was interrupted.

State remains intentionally ephemeral; dashboards, data sources and alert rules
are provisioned. Ordinary service restarts retain the SQLite database, session
bindings and logout markers. A host reboot/reset that discards Grafana's data
loses **both** sessions and markers: old cookies no longer authenticate, but old
in-flight OIDC callbacks are no longer protected by the lost cutoffs. Restoring
old session data without its markers can resurrect access. Do not truncate only
the marker table or persist only one half. A coordinated full reset is acceptable
because this instance's state is disposable; stop/drain authentication first so
old callbacks cannot cross the reset boundary. No new persistence is introduced
here.

### Grafana logout rollout

1. Temporarily block Grafana browser traffic, stop Grafana and discard its
   disposable state. Drain existing OAuth requests and reject old callback URLs
   across the reset boundary. This clears all pre-rollout sessions, which lack
   verified logout bindings; a service restart alone would not clear them.
2. Apply the integration while browser admission remains closed: patched
   Authentik runtime/Python package and migrations (PRs 26310 and 26565), patched
   Grafana with the enabled client settings, then the provider's back-channel
   Blueprint settings. On this shared host a single maintenance switch is fine:
   wait for all three to be ready before reopening. Ensure Authentik can reach the
   callback, which must reject unsigned requests. No new secret is needed.
3. Reopen Grafana and sign in afresh. Declarative dashboards, data sources and
   alerts are recreated. Fresh OAuth logins populate both Grafana's bindings and
   Authentik's RP-login records; do not rely on pre-upgrade IdP records being
   reconstructed.

Production acceptance still requires authenticated-request checks, not just
callback status:

- In separate browser sessions, verify Viewer/GrafanaAdmin mapping, denied admission
  without the access entitlement, avatar update/fallback and Grafana's logout redirect. End
  one Authentik session: its next authenticated Grafana API request must fail
  while an independent session still works. Repeat after the one-minute access
  token expires and ordinary Grafana/Authentik restarts; also test an abandoned
  unrelated Authentik flow before app logout.
- Verify fresh login after logout (including reused `sid`), duplicate and
  subject-only events, signing-key rotation/delivery retries, a callback racing
  logout, and IdP outage with an existing Grafana session. Test the reboot/reset
  boundary with authentication drained; there is no revocation continuity across
  database loss. Check administrative session termination, deactivation and group
  removal separately rather than assuming they emit equivalent logout events.

Package tests use a disposable loopback IdP and SQLite database, not live
Authentik or browsers. Configured callbacks and successful callback responses are
not production acceptance; the authenticated-request and independent-session
checks above remain required.

**Seerr:** experimental native OIDC pinned to
[PR #2715](https://github.com/seerr-team/seerr/pull/2715), revision `2e523125`.
Only users with Seerr's `access` entitlement may authenticate. A local patch
replaces permissions from `seerr_permissions` on each OIDC login (and account
linking), including for the owner account. The `admin` entitlement emits `[ADMIN]`;
ordinary `access` emits `[REQUEST]`. Per-user permission attributes do not bypass
these entitlements.

The mapping uses Seerr's uppercase
[permission names](https://github.com/seerr-team/seerr/blob/2e523125e8e7262af44309c70db20fe2d7ca28a3/server/lib/permissions.ts).
`[]` grants no permissions; missing/malformed claims and unknown names reject
login rather than preserving stale grants. Request quotas are unchanged. Local
permission-edit endpoints are disabled; password, media-server and Quick Connect
login are disabled. Permissions refresh on login, not continuously; revoke
existing Seerr sessions/API keys separately when immediate removal is needed.

Seerr's logout button clears its local session, then opens Authentik's provider
logout choices. Authentik is configured to send signed back-channel logout
requests to `/api/v1/auth/oidc/backchannel/authentik`. Seerr persists revocation
markers and checks them on API requests and OIDC callbacks, correlating the
verified issuer/client/subject and optional session ID. Existing sessions without
this metadata need a fresh login (or explicit session clearing during rollout).
Provider logout delivery uses Authentik's recorded application logins rather than
requiring an unexpired access token; test both fresh and aged sessions. Email
remains required.

### Initial Seerr provisioning and migration

These steps apply to fresh installs or clients predating the OIDC/logout patches,
not as a checklist of work still outstanding on every deployment.

1. Generate a client secret locally (for example, `openssl rand -hex 32`). Add
   the **same** `authentik-seerr-client-secret` value using `sops` to both
   `hosts/nixos/alcyone/secrets.yaml` and `hosts/nixos/merope/secrets.yaml`.
   Do not deploy until both encrypted files contain the key.
2. Before switching the client to OIDC-only, existing users must link Gablogin
   under **Profile → Settings → Linked Accounts** using their old login method.
   Matching emails are deliberately not auto-linked. Alternatively, start fresh
   and reconfigure Seerr's media-server/Sonarr/Radarr connections; Seerr state is
   disposable, and requester history is retained by Sonarr/Radarr tags.
3. Build through CI or natively on Merope (`aarch64-linux`). For initial setup,
   deploy Alcyone's provider before Merope's client. For the back-channel logout
   upgrade, deploy the patched client before enabling Alcyone's callback URI.
   Seerr reads its operator-owned declarative configuration; the database remains
   persistent. Back it up before the logout patch adds its revocation table.
   Existing sessions need a fresh login to acquire logout correlation metadata.
4. Verify admin/user permissions, an explicit override, demotion, rejected local
   permission edits, and rejection without shared group membership. Login is at
   `https://requests.m7.rs/login`.

## Revocation

Role changes apply on OAuth login; removing group membership is not immediate
application-session revocation. Disable application-local access and revoke its
sessions/API keys when immediate removal matters.

Back-channel logout is configured for Jellyfin, Immich, Seerr and Grafana, but is
not a blanket revocation guarantee. With the pinned Authentik and application
patches:

- Authentik PR 26310 records application logins independently of access-token
  expiry, allowing session-deletion notifications after tokens expire or are
  cleaned up. Migration backfills login records from retained access/refresh
  tokens; it cannot reconstruct records whose tokens are already gone. Verify
  aged sessions after upgrading rather than assuming migration coverage. PR 26565
  prevents an unrelated unfinished flow from swallowing a subsequent app logout.
  Delivery/retries and each administrative revocation path still need live checks.
- Jellyfin persists token-to-OIDC lineage and cascades delivered logout to Quick
  Connect descendants, preserving independent logins across restarts. Pre-lineage
  devices require explicit revocation and a fresh login; see the rollout above.
- Seerr's correlation and revocation markers survive restarts, but only sessions
  created after the back-channel patch carry the required identity metadata.
- Grafana rejects correlated browser sessions after delivered logout, including
  after ordinary service restarts. Pre-rollout sessions require explicit clearing;
  ephemeral database loss also loses cutoffs. Group changes alone are not a
  continuous role sync or a guaranteed logout event; see its staged rollout above.

Test fresh and aged logins, restart, Quick Connect and two independent sessions
when changing this behavior. A successful callback alone does not prove that
an authenticated API request is rejected or another device is unaffected.

## Recovery

Keep SSH/SOPS access, mailbox access and recovery material independent of the
IdP. Runtime secrets come from SOPS; never put them in Nix/store files or docs.

- **Authentik:** restore the PostgreSQL dump, `/var/lib/private/authentik` and
  original effective `authentik-key` into a matching version with services
  stopped. Dumps are under `/var/backup/postgresql`; both paths persist under
  `/persist` and enter [Borg backups](backups.md). Preserve the exact single-line
  key independently: changing it or normalizing it to a different value is not
  a formatting fix. Nix rollback does not undo DB migrations or Blueprint changes.
- **Jellyfin:** restore `data/jellyfin.db` and
  `plugins/configurations/Jellyfin.Plugin.OIDC.UserProviderMap.json` and
  `plugins/configurations/Jellyfin.Plugin.OIDC.SessionLineage.json` together
  under `/var/lib/jellyfin`. Migration backups were placed under
  `/persist/var/backup/jellyfin-oidc/`. No local-password administrator remains.
  Local recovery requires deliberately relaxing the startup guard and changing
  the intended account's authentication provider while stopped; Nix rollback
  alone cannot undo account migration. Avoid restoring a whole old DB just to
  change one account's login method.
- **Immich:** temporarily set `passwordLogin.enabled = true` and
  `oauth.autoLaunch = false` under `services.immich.settings`, then redeploy.
  Do not delete users or the database to reset authentication.
- **Grafana:** recover through SSH and declarative provisioning, not a retained
  local password. Its state is disposable: a coordinated full reset is acceptable
  with Grafana stopped and authentication drained, but never restore old sessions
  without their revocation markers.
- After rotating the SMTP password, restart Dovecot as well as Authentik; the
  mail password declaration has no Dovecot restart hook.

## Remaining work

- Verify recovery-email delivery/reset, restored MFA browser login and recovery
  using independently stored key material. Check that failed/abandoned recovery
  MFA leaves the old password unchanged, and that password/profile changes and
  authenticator setup require fresh credentials (including direct flow URLs).
  Test both enrolled and unenrolled accounts. The isolated restore result is
  recorded in [backups](backups.md), not proof of these paths.
- Exercise current roles/demotions, native/mobile sign-in, logout and IdP outage;
  review capacity under sustained load. Audit Jellyfin plugin subject-validation,
  provider-scoping and logout limitations before widening use.
- Complete and record the [mail/DAV live acceptance checks](mail-auth.md#live-acceptance):
  IMAP/SMTP, DAV read/write, refresh/revocation, existing connections and delivery
  during IdP failure. OAuth is implemented and mail/DAV intentionally share one
  grant. Browser-session deletion does not revoke refresh tokens; app-password
  labels do not impose per-application scopes. Verify unattended oama/GPG behavior
  without breaking the other accounts.
- Track the authenticator-deletion API's missing fresh-authentication check
  ([upstream issue 6798](https://github.com/goauthentik/authentik/issues/6798));
  the sensitive-change flows do not close that separate API path.
- Choose phone notifications for new authorizations, MFA/recovery and admin
  changes. No phone-push transport or custom event rules are declared.

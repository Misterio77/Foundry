# Gablogin / Authentik

Describes the checked-in configuration, not deployment status. Sources:
[service](../hosts/nixos/alcyone/services/authentik.nix),
[Blueprints](../hosts/nixos/alcyone/services/authentik/),
[Jellyfin](../hosts/nixos/merope/services/media/jellyfin/),
[Immich](../hosts/nixos/merope/services/immich.nix),
[Grafana](../hosts/nixos/alcyone/services/grafana/default.nix),
[Seerr](../hosts/nixos/merope/services/media/jellyseerr.nix).

## Access

- `auth.m7.rs` is public, including the admin UI; authentication, MFA and
  permissions protect administration, not a separate network ACL. Backend
  listeners are loopback-only; metrics allow only loopback/tailnet clients.
- Login accepts WebAuthn **or TOTP**, with enrollment required when neither
  exists. WebAuthn requires user verification but not hardware-key attestation.
  Sessions persist for 30 days. Branding/default locale is Gablogin/`pt-BR`;
  saved user preferences can override the locale.
- Email password recovery expires after 15 minutes and allows five attempts per
  account per 15 minutes. It neither removes MFA nor reactivates disabled users;
  reset returns to normal login rather than creating an authenticated session.
  Email uses `auth@m7.rs` through tailnet-restricted SMTP at `mail.m7.rs:465`.

Application membership is shared; `admins` also grants ordinary access.
Neither group grants Authentik administration. Roles below are OIDC claims,
not Authentik RBAC roles or additional membership groups.

| Group | Jellyfin roles | Immich role | Grafana organization role |
| --- | --- | --- | --- |
| `users` | `jellyfin-users` | `user` | `Viewer` |
| `admins` | `jellyfin-users`, `jellyfin-admins` | `admin` | `Admin` |

Each provider/client uses its own `jellyfin_roles`, `immich_roles` or
`grafana_roles` scope. Membership is assigned manually, never by the Blueprint.
On migration, populate the shared groups before deploying Alcyone, then Merope.
Keep old `jellyfin-access` membership until Merope's client switches. Access
bindings update in place by application/order; separately audit extra manual
bindings. Old app-specific groups and removed LDAP/Calibre objects are not
implicitly deleted from Authentik's database.

## Application behavior

**Jellyfin:** admits either role, manages all-library access and admin status,
allows audio transcoding and disables video transcoding for everyone. New
accounts can be created; automatic username migration and email linking are off.
Existing subject-to-user bindings remain authoritative. The startup guard
rejects local authentication providers and missing/conflicting identity maps.
Gravatar pictures sync on OAuth login, replacing existing Jellyfin profile images;
missing pictures leave the existing image alone.

The web client uses same-tab Gablogin, hides password controls, and returns to
login on authenticated 401s. Explicit logout clears local state before opening
Authentik's application logout page. Native clients use Quick Connect:
`https://media.m7.rs/connect`, optionally `?user_code=012345`. QR codes carry only
the public six-digit code; approval remains explicit and the tab can then close.

**Immich:** OAuth-only, auto-launch and auto-registration enabled. Existing
accounts can link by matching email on first OAuth login: verify the intended
email/identity before admission. Admin status syncs from `immich_role`; quota
syncs from the user's `immich_quota` attribute (GiB, default 8; -1 unlimited).
Browser/mobile access remains tailnet-only, except the public `/share` proxy.

**Grafana:** OAuth-only with strict role mapping and no email-based linking or
server-admin assignment. Anonymous tailnet viewing remains enabled. State is
intentionally ephemeral; dashboards, data sources and alert rules are provisioned.

**Seerr:** experimental native OIDC pinned to
[PR #2715](https://github.com/seerr-team/seerr/pull/2715), revision `2e523125`.
Only `users`/`admins` may authenticate, but Seerr permissions remain local:
new accounts receive Seerr's default permissions, not Authentik-derived admin
status. Existing users must sign in using their old method and link Gablogin
under **Profile → Settings → Linked Accounts** before using OIDC login. Matching
email addresses are not automatically linked. Existing login methods stay enabled.

### Seerr preview rollout

1. Generate a client secret locally (for example, `openssl rand -hex 32`). Add
   the **same** `authentik-seerr-client-secret` value using `sops` to both
   `hosts/nixos/alcyone/secrets.yaml` and `hosts/nixos/merope/secrets.yaml`.
   Do not deploy until both encrypted files contain the key.
2. Build through CI or natively on Merope (`aarch64-linux`); do not emulate the
   application build on an x86 workstation. Deploy Alcyone's provider first,
   then Merope's client. The pre-start script requires an initialized
   `settings.json` and patches only OIDC settings and the public application URL.
3. Before the first preview start, the stopped service's config directory is
   copied once to `/var/lib/private/jellyseerr/config.pre-oidc` (also persisted).
   Copy that snapshot off-host before treating rollback as tested. It contains
   credentials; keep it private. Later starts never overwrite it.
4. Link an existing administrator account first, then verify a fresh OIDC login,
   ordinary user access, new-account permissions and rejection without shared
   group membership. Login is at `https://requests.m7.rs/login`.

To roll back, stop Seerr and deploy a configuration using the release package
**without** the OIDC pre-start script (prevent it starting during restoration).
Keep the migrated config separately, then restore the whole `config.pre-oidc`
snapshot to `config` with ownership/modes preserved before starting the release.
Restoring just `settings.json` does not undo database migrations; requests and
other changes made since the snapshot will be lost. A Nix generation rollback
alone is insufficient. Do not remove the snapshot until the preview is accepted.

## Revocation

Role changes apply on OAuth login; removing group membership is not immediate
application-session revocation. Disable application-local access and revoke its
sessions/API keys when immediate removal matters.

Back-channel logout is configured for Jellyfin and Immich, but is not a blanket
revocation guarantee. With the pinned Authentik/Jellyfin plugin:

- Authentik session deletion dispatches against unexpired access tokens;
  Jellyfin's unrefreshed ten-minute token can age out of notification delivery.
- Jellyfin's session correlation is in memory. Restart fallback can widen
  revocation to all of a user's tokens; Quick Connect is not reliably scoped
  to the originating browser session.
- Grafana sessions can survive IdP group/session changes.

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
  `plugins/configurations/Jellyfin.Plugin.OIDC.UserProviderMap.json` together
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
  local password. Do not reset its database as a routine OAuth repair.
- After rotating the SMTP password, restart Dovecot as well as Authentik; the
  mail password declaration has no Dovecot restart hook.

## Remaining work

- Verify recovery-email delivery/reset, restored MFA browser login and recovery
  using independently stored key material. The isolated restore result is
  recorded in [backups](backups.md), not proof of these paths.
- Exercise current roles/demotions, native/mobile sign-in, logout and IdP outage;
  review capacity under sustained load. Audit Jellyfin plugin subject-validation,
  provider-scoping and logout limitations before widening use.
- Mail/DAV device credentials are **not integrated**. Prototype OAuth against a
  disposable mailbox; test IMAP, SMTP, refresh/revocation, existing connections,
  mailbox paths and delivery during IdP failure before migrating real clients.
  Separate DAV credentials from mail and revisit GPG-gated background sync without
  breaking other accounts. Browser-session deletion does not revoke refresh
  tokens; app-password labels do not impose per-application scopes.
- Choose phone notifications for new authorizations, MFA/recovery and admin
  changes. No phone-push transport or custom event rules are declared.

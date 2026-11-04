# Authentik pilot operations

Pilot test-activated on Alcyone on 2026-11-03. See [the rollout plan](idp.md)
for the wider migration. An isolated restore record is included below; it does
not prove independent key recovery or browser MFA after restoration.

## Before deployment

- Verify Alcyone's CPU, available RAM and disk space over SSH. Upstream's small
  deployment guidance is at least two cores and 2 GB RAM; account for existing
  services rather than treating that as spare capacity.
- Add `authentik-key` and `authentik-grafana-client-secret` to
  `hosts/nixos/alcyone/secrets.yaml` using SOPS. Generate each independently with
  `openssl rand -hex 32`, keeping each value on one line. Never paste
  values into chat or Nix files. Preserve the Authentik key independently for
  disaster recovery; changing it is not a routine credential rotation.
- Build with `nixos-rebuild build --flake .#alcyone --no-link`, then deploy with
  `./deploy.sh alcyone`. The wrapper uses a temporary `test` activation, not a
  persistent `switch`; do not confuse a successful test with a durable rollout.
- Confirm the expected revision using `ssh alcyone -- nix flake metadata self
  --json`. An uncommitted/local test build may not report a clean revision;
  compare `/run/current-system` with the built output too.

The input is community `authentik-nix` at `5d339402`, packaging Authentik
2026.8.5 with its own nixpkgs. The reviewed GitHub security advisories were fixed
by this version; recheck advisories before subsequent deployments. The shared
PostgreSQL cluster remains on major version 14.

Blueprints live under `hosts/nixos/alcyone/services/authentik/`: `foundry.yaml`
contains shared authentication/MFA setup, while `grafana.yaml`, `immich.yaml`,
`calibre-web.yaml` and `merope-ldap.yaml` own their respective integrations.
Grafana and Immich explicitly apply the shared Blueprint; the Merope LDAP outpost
applies the Calibre-Web provider Blueprint before finding its provider by name.
`recovery.yaml` owns password recovery. Object names and existing identities are
preserved when moving entries between files.

## Bootstrap and access

1. Immediately open `https://auth.m7.rs/if/flow/initial-setup/` from the tailnet
   after deployment. Set the `akadmin` password privately. No bootstrap password
   or API token is stored in Foundry. Do not leave initial setup unclaimed.
2. Confirm the `Foundry - private identity pilot` Blueprint applied successfully
   in the admin interface, along with `Foundry - Grafana`. The shared Blueprint
   explicitly depends on the default flows and scope
   mappings, and modifies the default MFA stage to accept WebAuthn or TOTP,
   offering enrollment when neither is configured. WebAuthn requires user
   verification. TOTP is an explicit compatibility option for qutebrowser,
   which the operator reports does not support FIDO; it is not phishing-resistant.
3. Enroll your hardware keys and TOTP, then test fresh browser logins using each
   method. The initial setup flow is a bootstrap exception, not evidence of
   enforced MFA. WebAuthn alone
   does not prove a credential is a physical YubiKey: no device-attestation
   allowlist is configured. Choose the intended hardware keys during enrollment.
4. Create a separate ordinary user, with no Authentik superuser membership, for
   Grafana. Enroll their MFA credential and add them to `grafana-admins`
   (Grafana organization Admin) or `grafana-users` (Viewer). No one receives
   membership from the Blueprint, and neither group grants Grafana server-admin
   or Authentik admin rights.
5. At `https://dash.m7.rs/login`, choose Authentik. OAuth usernames use the
   `preferred_username` claim directly; email-based linking remains disabled.
   Local password/form and HTTP Basic authentication and bootstrap-admin creation
   are disabled. Anonymous tailnet viewing is intentionally unchanged. Recovery
   is through independent SSH/SOPS access and declarative redeployment, not a
   local Grafana password. See the one-time state reset below before rollout.

Public registration is not added. `auth.m7.rs` is configured for public HTTPS,
including the portal, OIDC endpoints and email password recovery. The admin UI
is also reachable and remains protected by Authentik authentication, MFA and
permissions, not a separate network ACL. Backend and metrics listeners stay
on loopback; nginx restricts `/metrics` and `/metrics/worker` to loopback and
tailnet clients. Headscale detects tailnet ACLs in individual locations too,
so `auth.m7.rs` gets private DNS for tailnet clients while remaining public
outside the tailnet. Prometheus keeps scraping both through `auth.m7.rs`.
The same metrics-only restriction covers Headscale, Jellyfin and the shared
host nginx exporters; it does not restrict their public application routes.
Phone notifications are not configured.

## Acceptance checks before relying on it

- Verify `authentik`, `authentik-worker`, `authentik-migrate`, nginx and PostgreSQL
  health; check migration/Blueprint failures without dumping credentials.
- Check public HTTPS works for `auth.m7.rs`, while `/metrics` and
  `/metrics/worker` reject public clients and work over the tailnet. Check
  private DNS generation and hostname-based scrapes, and confirm backend and
  metrics listening sockets remain loopback-only.
- Test hardware-key and TOTP enrollment, fresh login using either method,
  absence of password-only fallback, and a second key. Arrange independent
  administrative recovery.
- Confirm an unbound user cannot authorize Grafana and Viewer/Admin mappings are
  correct, without granting Grafana server-admin rights. Verify local password
  and HTTP Basic authentication are disabled, including on a fresh database.
- Test token refresh after ten minutes, logout in both directions and IdP
  downtime. Grafana has local sessions; group removal or IdP session deletion
  is not a promise of immediate Grafana session revocation.
- Confirm Prometheus scrapes both Authentik targets and existing service-down
  alerts cover them. Backup-age alerting is still outstanding.
- Start `postgresqlBackup-authentik`, then the Borg job, and verify an off-host
  archive includes the SQL dump and Authentik files. Inspect archive metadata,
  not dump contents. Restore-test in isolation before making the IdP authoritative.

## Grafana OAuth-only rollout

The OAuth-only configuration requires a one-time reset of Grafana's ephemeral
state. Do not remove the username prefix against the old database: a plain
username could match the former local bootstrap administrator. The encrypted
`grafana-gabriel-password` entry may remain in SOPS, but is no longer consumed.

Coordinate the reset with activation of the new configuration, before allowing
OAuth logins. Stop Grafana, remove its ephemeral data directory
(`/var/lib/grafana/data`), activate the OAuth-only configuration, then start
Grafana. This deletes users, sessions, preferences and alert runtime state;
provisioned dashboards, data sources and alert rules are reconstructed. Never
remove the data directory while Grafana is running. A service restart alone
will not reset the database. The reset ends any ongoing session-lifecycle test.

After activation, verify there is no bootstrap administrator or local login
form, HTTP Basic authentication cannot authenticate, and a fresh OAuth login
uses the plain username with the expected organization role. Preserve the
existing `allow_assign_grafana_admin = false` and strict group-role mapping.
Do not add email-based linking to work around account collisions.

Grafana state remains intentionally nonpersistent. An IdP outage preserves
anonymous tailnet viewing but may prevent authenticated administration; this is
accepted because recovery and provisioning use independent SSH/Nix/SOPS access.
No local Grafana recovery account is retained by this design.

## Immich OIDC rollout

Configured for Authentik-only login; live browser/mobile verification is still
pending. Existing Immich user records, photo ownership, admin roles, API keys
and sessions are retained. Password login is disabled and browser login
launches OAuth automatically. This changes authentication, not photo storage.

- Generate one new single-line client secret with `openssl rand -hex 32` and
  privately add the **same value** as `authentik-immich-client-secret` to both
  `hosts/nixos/alcyone/secrets.yaml` and `hosts/nixos/merope/secrets.yaml` using
  SOPS. Never put the value in chat, Nix, or the Blueprint. Alcyone injects it
  through the Authentik environment; Merope loads it through systemd credentials
  into Immich's runtime JSON configuration.
- Deploy Alcyone first. Confirm `Foundry - Immich` applied, then add the
  intended Authentik account to `immich-users`. This group grants access only
  to Immich, not Grafana or IdP administration.
- Before deploying Merope, confirm the Authentik account's email matches the
  existing Immich account. Immich 3.3.5 automatically links matching emails at
  first OAuth login if the Immich account is not already linked to another
  subject. Review both the email and group membership deliberately: an allowed
  Authentik identity with that email can take over the matching Immich account.
  If emails cannot match, temporarily retain password login, link OAuth from
  the existing account's user settings, then disable password login again.
- Deploy Merope and sign in through `https://photos.m7.rs`. Check that the
  existing library and admin status remain attached to the same account.
  Auto-registration is enabled for authorized `immich-users` without an
  existing account; those new accounts receive ordinary user privileges.
  No admin/quota claims are sent, so existing local permissions are preserved.
- Test mobile OAuth with the existing server URL. The provider allows exactly
  the browser login, user-settings linking, and `app.immich:///oauth-callback`
  redirects. `photos.m7.rs` still requires tailnet access for browser and mobile
  clients; making the IdP public does not expose the photo service.
- Public `/share` handling remains unchanged. Back-channel logout is configured
  at `https://photos.m7.rs/api/oauth/backchannel-logout`; this is not a claim
  that every existing session or API key is revoked by IdP logout.

Recovery is SSH plus declarative configuration, not a permanent local login:
restore `services.immich.settings.passwordLogin.enabled = true` and set
`services.immich.settings.oauth.autoLaunch = false`, then redeploy Merope.
Do not delete Immich users or its database to reset authentication.

## Calibre-Web LDAP rollout

See [the Calibre-Web runbook](calibre-web-auth.md) for the staged rollout,
Authentik app-password self-service, existing-user mapping and removal of local
password hashes. This integration is prepared but not yet verified live.

## Gablogin branding and Portuguese defaults

The default brand selects `pt-BR` through `attributes.settings.locale`. Authentik
uses this for both its frontend locale hint and its backend `default_locale`;
there is no separate writable `default_locale` Blueprint field. Explicit user,
session or URL language selections can override the frontend default. Test in a
clean browser session rather than treating a saved English selection as a
failure of the default.

Flow names/titles are stored text, not translated UI messages. The shared
Blueprint localizes login, logout, account settings, password change, MFA setup,
application authorization/logout and access requests; recovery owns its own
Portuguese wording. Application logout now reads `Você saiu de %(app)s`.
The native `Voltar ao início` footer exits to the portal, without pretending to
rewind a partially completed flow.

The copied upstream Blueprints also localize password/account form labels and
placeholders, password-policy feedback, account-edit denial messages and default
names for newly enrolled authenticators. Existing device names and user-chosen
labels are not renamed. Substitutions fail the build if their upstream text
changes, and preserve policy code rather than maintaining a second copy of its
permission checks. The pinned upstream Portuguese catalogs are incomplete,
particularly in the admin interface; these changes do not claim to translate
all upstream UI strings or third-party application screens.

Before calling the rollout verified:

1. Publish/deploy the reviewed changes through the normal signed workflow, then
   confirm the deployed revision. No deployment or sudo is performed by these
   offline localization checks.
2. In a clean session, check Portuguese login, recovery, password/account forms,
   both MFA setup screens and application logout, including Immich. Confirm
   light/dark logos, favicon and the footer link render correctly.
3. With a disposable account, verify recovery email delivery, password reset and
   a fresh normal login requiring MFA. Do not reset the operator's credentials
   merely to test labels. Password recovery remains a separate acceptance gate.

Offline verification on 2026-11-04 built the Blueprint package and full Alcyone
system, and parsed the four modified default Blueprints. Object identifiers and entry counts were
unchanged; an AST comparison confirmed the account-edit policy changed only its
three display messages. Earlier flow-label/footer importer checks ran in a
rolled-back live transaction; the newest form/device translations still need
post-deployment verification.

## Email password recovery

Configured, with live delivery/reset verification still pending. The login page
links to `default-recovery-flow`, also selected by the default brand. Recovery
defines the email-verification stages directly, following the pinned upstream
example. That example is not auto-instantiated and cannot be a
`metaapplyblueprint` dependency. The flow reuses the default password-change
prompt, password policy and never-create user-write stage:

- Identification does not reveal whether the account exists.
- Recovery links have a configured 15-minute expiry, with five email attempts
  per account per 15 minutes. The existing password-change policy validates
  the new password, and the flow never creates users.
- Email verification does not reactivate disabled users or remove MFA devices.
- No automatic-login stage is bound. After writing the password,
  a redirect discards recovery context and starts normal authentication,
  including the configured MFA stages. Email possession alone is not an SSO
  session or an MFA-reset mechanism.
- Global email settings authenticate as the dedicated send-only `auth@m7.rs`
  account at `mail.m7.rs:465`, using implicit TLS and certificate verification.
  Both Authentik and the mail server use `authentik-mail-password` from Alcyone's
  SOPS file at runtime; the mail module hashes it before passing it to Dovecot,
  as for the other service accounts. No password enters the Nix store. This uses the existing
  tailnet-restricted submission service, not the trusted local relay path;
  Authentik needs tailnet access to mail if moved to another host.
  Until all mail passwords have a restart hook, restart `dovecot.service` after
  rotation so SMTP authentication uses the new hash.

Set usable, unique recovery email addresses before relying on this. For the
operator, preserve mailbox access independently of the IdP. After deployment,
use a disposable account to check external delivery, password reset, subsequent
MFA login, and rejection of invalid/expired links. Confirm the recovery Blueprint
applied successfully and Prometheus still scrapes both targets. No successful
live recovery is claimed by these configuration checks.

On 2026-11-04, the revised Blueprint passed Authentik's real importer against the
live database inside a rolled-back transaction. The five stage bindings, password
policy, login-page/brand recovery links and unchanged MFA settings were checked.
No email was sent, no password was reset, and the test did not enable the flow.

Lost MFA devices and administrative disaster recovery still require independent
SSH/management access; this flow only recovers the account password.

## State and recovery

- The database/user are both `authentik`, using the existing local PostgreSQL
  cluster and peer authentication.
- DynamicUser state is persisted at `/persist/var/lib/private/authentik`;
  `/var/lib/authentik` is systemd's public symlink. Uploaded media and other file
  storage are in that state directory. SQL dumps are persisted under
  `/persist/var/backup/postgresql`.
- Each persist snapshot waits for a successful native PostgreSQL dump; Borg
  reads the latest read-only snapshot and includes the dump and Authentik state.
  This makes dump success a prerequisite for new persist snapshots. The
  existing snapshot/off-host schedule and retention remain unchanged.
- Recovery requires the database dump, mutable files, original Authentik key,
  and independently accessible SSH/SOPS credentials. Do not make recovery
  depend on Authentik or its email integration. Restore the database into a
  matching application version, with Authentik stopped, and test keys/login
  before reconnecting clients.
- Nix rollback does not undo database migrations or Blueprint changes. Removing
  the YAML file does not delete objects it created. Take a consistent backup
  before upgrades and use a database-aware restore if needed.

## Verification record (2026-11-03)

- Full host build and `deploy.sh alcyone` test activation succeeded. Verified
  `/run/current-system` against the built output (`0ip3g9f2…`). Flake metadata
  reports a local/dirty source, not a deployed clean commit. This test activation
  can be replaced by a reboot or the existing automatic upgrades; no production
  bookmark was moved or pushed.
- The host has one vCPU and about 1 GiB RAM. Deployment proceeded with the
  operator's explicit acceptance of undersizing; resizing remains planned.
  During interactive testing, swap usage reached about 1.5 GiB with active paging
  and substantial I/O pressure. More swap is not a substitute for additional RAM.
- Initial setup returned HTTPS 200 over loopback; the operator reported setup
  complete. Public HTTPS returned 403. Headscale generated both private DNS
  records, and Grafana OIDC discovery worked over the tailnet.
- The Foundry Blueprint reached `successful`. Listener sockets are loopback-only,
  both Prometheus targets are up, and Grafana's database health is OK.
- Blueprint YAML parsing and Grafana role/login-expression tests passed.
- The native database dump, persist snapshot and off-host Borg job completed
  successfully. The dump was nonempty and the state persistence mount exists.
  A separate archive-content listing encountered a repository lock; content
  inspection and an isolated restore test remain pending. Do not break a live
  Borg lock merely to complete this check.
- The operator enrolled FIDO and TOTP credentials and requested support for
  both because qutebrowser lacks FIDO support. The pilot intentionally allows
  either MFA method rather than enforcing hardware-key-only login.
- Confirmed the updated live MFA stage accepts both `webauthn` and `totp` and
  requires enrollment when neither exists. Blueprint changes may wait for
  periodic discovery after a restart; an explicit discovery task was dispatched
  for this update.
- The operator reported a successful Grafana login using WebAuthn. TOTP login,
  separate-user role/access boundaries, refresh/logout/revocation, and IdP
  outage behavior still need browser tests. Recovery email, phone notifications
  and backup-age alerts remain unconfigured.

## Verification record (2026-11-04)

- Alcyone was cold-migrated to a replacement VM with one vCPU, about 2 GiB RAM,
  and a 64 GiB GPT disk. Authentik and its worker are active after a disk boot;
  the authentication flow returns HTTPS 200 over the tailnet. Public access is
  still rejected with 403. This improves capacity but remains below upstream's
  two-core guidance; sustained-load observation is still needed.
- A fresh PostgreSQL dump, persist snapshot, and off-host Borg backup to Merope
  completed successfully on the replacement. Archive
  `alcyone-alcyone-2026-11-04T13:40:55` contains the nonempty Authentik SQL dump
  and mutable Authentik files. Archive metadata/content-list inspection passed;
  an isolated restore was subsequently tested as recorded below.
- The operator confirmed successful Grafana login using TOTP with a separate
  ordinary Authentik user in `grafana-admins`, and successful WebAuthn in a
  separate test. This confirms login with the allowed group, not denial for an
  unbound user, Viewer mapping, or absence of server-admin privileges.
- The operator subsequently verified that removing the Grafana groups denies
  fresh authorization and `grafana-users` grants Viewer access; the previous
  `grafana-admins` test covered organization Admin. An existing Grafana session
  survived group removal immediately; refresh-time behavior is not yet proven.
- Remaining browser checks: absence of Grafana server-admin privileges,
  logout/revocation, and IdP downtime. Group removal denied fresh authorization
  but the existing authenticated profile remained usable after almost twelve
  minutes. A later refresh-token deletion experiment ended with the approved
  Grafana state reset, before a conclusive refresh failure was observed.
  OAuth-only Grafana was deployed at revision `55ba6ed5`; its state was reset,
  and the operator confirmed fresh login with a plain username. Independent
  IdP administrative recovery, notifications, and backup-age alerts remain open.
  Local Grafana recovery was deliberately dropped in favor of independent
  declarative recovery.
- Archived Authentik SQL dump retrieval and gzip integrity checks passed, as
  did dry-run extraction of the mutable files. These are retrieval checks, not
  proof of a working database/application restore.

## Isolated restore drill (2026-11-04)

A one-off NixOS restore test was built and run on Atlas using the pinned
Authentik 2026.8.5 module and PostgreSQL 14. The disposable KVM VM had only
loopback: QEMU was given `-nic none`, and the test asserted the absence of other
interfaces before importing anything. It could not send email, contact clients,
or reach production. Production services and database were not stopped or
modified by the restore.

Inputs came from Borg archive `alcyone-alcyone-2026-11-04T13:40:55`: the native
SQL dump and `var/lib/private/authentik` files. The runtime-effective secret key
was retrieved separately from the running production service for this drill.
All private inputs, logs, shared exchange files and VM state were confined to
mode-0700 scratch directories under Atlas's runtime tmpfs, outside the Nix store
and repository, and removed after the driver exited. Remote export staging was
also removed.

Verified:

- The native SQL dump imported with `ON_ERROR_STOP`; it includes `CREATE
  DATABASE` and a reconnect, so import it into the maintenance database after
  dropping the disposable empty `authentik` database, not in one transaction.
- Authentik migration, server, worker and the authentication-flow HTTP endpoint
  started against the restored database/files.
- The configured secret key matched the separately injected effective key.
- Grafana application/groups and the OIDC signing private key were usable.
- Restored TOTP and WebAuthn device records existed. No credential values or
  device identifiers were displayed.
- Anonymous administrative API access was denied. A new five-minute API token
  created through management access for the restored administrator successfully
  accessed the live administrative API. The token was deleted in `finally`;
  it existed only in the disconnected clone and was never printed.

This proves a working database/application restore and management-assisted API
recovery. It does **not** prove browser login with restored MFA credentials,
recovery through independently stored key material after loss of production,
or a complete external-client/OIDC recovery. Those remain separate checks.

### Secret-key recovery hazard

The raw SOPS `authentik-key` contained an internal newline. The unquoted
`AUTHENTIK_SECRET_KEY=` template caused systemd to load only the first line;
comparison against the running process confirmed that this 64-character value
was the actual production key. The first restore attempt using the full raw
value failed the explicit key-equality check. Retrying with the effective key
passed the complete drill. Production's key was not changed.

The operator subsequently normalized the SOPS entry privately to the
**existing effective first line**, preserving the production key. Preserve that
exact key independently before making the IdP authoritative.
Do not concatenate the lines, quote the full multiline value, switch directly
to a file-backed full value, or generate a replacement as a formatting fix:
those change the effective key. New keys should use a non-wrapping generator
such as `openssl rand -hex 32`. Never print existing key material or put it in
Nix expressions or test fixtures committed to the repository.

The temporary test harness was intentionally not retained in Foundry. This is
a record of the completed drill, not a maintained restore tool or CI check.

Implementation details found during live testing: listener settings require
lists, Blueprint retrieval rejects symlinks resolving outside `blueprints_dir`,
and certificate discovery needs an existing directory even when unused. Keep
these constraints when changing the module or combining Blueprint files.

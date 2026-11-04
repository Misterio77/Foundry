# Authentik pilot operations

Pilot test-activated on Alcyone on 2026-11-03. See [the rollout plan](idp.md)
for the wider migration. This is not a restore-test record.

## Before deployment

- Verify Alcyone's CPU, available RAM and disk space over SSH. Upstream's small
  deployment guidance is at least two cores and 2 GB RAM; account for existing
  services rather than treating that as spare capacity.
- Add `authentik-key` and `authentik-grafana-client-secret` to
  `hosts/nixos/alcyone/secrets.yaml` using SOPS. Generate them independently with
  `openssl rand -base64 60` and `openssl rand -hex 32`, respectively. Never paste
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

## Bootstrap and access

1. Immediately open `https://auth.m7.rs/if/flow/initial-setup/` from the tailnet
   after deployment. Set the `akadmin` password privately. No bootstrap password
   or API token is stored in Foundry. Do not leave initial setup unclaimed.
2. Confirm the `Foundry - private identity pilot` Blueprint applied successfully
   in the admin interface. It explicitly depends on the default flows and scope
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

Public registration is not added. The portal is tailnet/loopback-only; Headscale
should discover the vhost and publish private DNS records automatically. Public
DNS must still resolve to Alcyone for ACME's HTTP challenge. Backend and metrics
listeners are loopback-only. Mail, DAV, Headscale enrollment and media services
are unchanged. SMTP/recovery email and phone notifications are not configured.

## Acceptance checks before relying on it

- Verify `authentik`, `authentik-worker`, `authentik-migrate`, nginx and PostgreSQL
  health; check migration/Blueprint failures without dumping credentials.
- Check public access is rejected, tailnet HTTPS works and DNS contains
  `auth.m7.rs`. Check actual listening sockets, including metrics.
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
  no isolated restore has been performed.
- The operator confirmed successful Grafana login using TOTP with a separate
  ordinary Authentik user in `grafana-admins`, and successful WebAuthn in a
  separate test. This confirms login with the allowed group, not denial for an
  unbound user, Viewer mapping, or absence of server-admin privileges.
- The operator subsequently verified that removing the Grafana groups denies
  fresh authorization and `grafana-users` grants Viewer access; the previous
  `grafana-admins` test covered organization Admin. An existing Grafana session
  survived group removal immediately; refresh-time behavior is not yet proven.
- Remaining browser checks: absence of Grafana server-admin privileges, token
  refresh after ten minutes, logout/revocation, and IdP downtime. Independent
  IdP administrative recovery, isolated restore, notifications, and backup-age
  alerts also remain open. Local Grafana recovery was deliberately dropped in
  favor of OAuth-only access and independent declarative recovery.
- Archived Authentik SQL dump retrieval and gzip integrity checks passed, as
  did dry-run extraction of the mutable files. These are retrieval checks, not
  proof of a working database/application restore.

Implementation details found during live testing: listener settings require
lists, Blueprint retrieval rejects symlinks resolving outside `blueprints_dir`,
and certificate discovery needs an existing directory even when unused. Keep
these constraints when changing the module or combining Blueprint files.

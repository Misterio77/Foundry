# SOGo 6 integration

Work in progress: alcyone's native service, Authentik client, nginx routing and
backups are configured and the full system builds. Nothing has been deployed.
Isolated systemd lifecycle validation passes; native browser/provider validation
remains a deployment gate.

## Sources and patches

Both components use upstream `v6.0.0-alpha2` archives, content-pinned by Nix.
`oidc.patch` includes backend OIDC PR #88 (head
`b07b4ca078f0dc8d21b8ce5591407424afaa78aa`) plus authentication, refresh,
SMTP/TLS and avatar fixes. `ui.patch` includes frontend OIDC changes from
`f4ee0be8ca4b6225e6d152446cbecc4e0d21d2f2`, login/logout/avatar changes and the
bounded recurrence helper. `dav.patch` captures the direct-storage adapters.
No pilot database, credentials, compose configuration or built frontend is vendored.
Python application changes and pytest tests are carried in patches.

`identity.patch` and `production.patch` replace LDAP lookup with verified OIDC
identity, pin the mailbox and subject, require HTTPS public/logout URLs, constrain
Host/CORS/ticket origins, set Secure binding cookies and disable admin APIs.

`dav-production.patch` adds token-scoped DAV principal/home discovery, collection
privilege checks and mixed VEVENT/VTODO routing. UUID principals and administrator
`dav_principal` overrides are independent of `mail_account`. Writes require the
original browser ETag and current server snapshot ETag; conditional DAV writes
also protect the remaining read/write race. `ui-dav.patch` carries versions through
forms, inline actions and confirmation dialogs without refreshing away dirty edits.

The production overlay also:

- rejects unsupported collection/list/import/share/subscription/scheduling/reminder
  and export routes before constructing SQL-backed interfaces;
- rejects scoped deletions rather than letting upstream ignore recurrence arguments;
- creates only preferences on OIDC onboarding, not SQL content mirrors or remote folders;
- loads OIDC profile/UI settings without a directory source; discovered calendars
  default to visible without overriding explicit subscription opt-outs;
- preserves absent task start/due dates through parsing, API round trips and sorting;
- prevents opening an invitation email from automatically processing iMIP;
- checks fresh userinfo entitlement claims and pinned identity on every token check,
  even when introspection still reports the token active;
- supports Unix PostgreSQL/Redis sockets and replaces authoritative startup settings
  on restart, failing closed if they cannot be applied.

## Native service

`modules/nixos/sogo6.nix` provides API/UI units, a dedicated PostgreSQL role/database,
an ephemeral Unix-socket Redis instance, systemd credentials and sandboxing.
`hosts/nixos/alcyone/services/sogo6.nix` supplies the production settings and routes
`https://mail.m7.rs` through its existing certificate and tailnet ACL. API request
logging is suppressed to avoid recording OAuth callback codes.

The static Authentik blueprint creates a separate confidential `sogo` client with
strict callback, S256 and an exact application-only logout exception. It requires
both Mail and DAV access. The existing `mail-and-dav` client/grants are untouched.
The operator-supplied SOPS secret is shared through runtime credentials/environment,
not copied from the pilot or embedded in the store.

The `sogo6` database joins the dump → snapshot → Borg chain. Generated encryption
and voucher keys live in persisted `/var/lib/sogo6` and are backed up with it.
Startup refuses to regenerate missing keys for an initialized database. Redis
sessions are neither persisted nor restored. See [recovery notes](../../docs/backups.md).
No Celery worker or reminder scheduler is enabled; Mail operations are synchronous,
and unsupported DAV job paths are rejected.

## Checks

```sh
nix build .#sogo6-server .#sogo6-ui --no-link
nix build .#nixosConfigurations.alcyone.config.system.build.toplevel --no-link
```

Native package and full alcyone builds pass. The backend runs selected tests in
SOGo's existing pytest harness via `pytestCheckHook`, not the full upstream suite.
Coverage includes identity/session restoration, directory-free authentication,
origin/cookie restrictions, discovery, privileges, URL fencing, mutation gates,
bootstrap behavior, entitlement checks and blueprint policy expressions.

Real isolated Radicale tests cover task/event/contact stale-write rejection,
opaque properties, event alarms, grouped contact labels, partial birthdays, absent
task dates and conditional deletion. Frontend Jest checks cover conditional
headers, dirty-form retention, conflict handling, login/logout and avatars.

`test_foundry_deployment.py` additionally checks evaluated non-secret Nix settings
and built native executables. Supply `SOGO_TEST_DEPLOYMENT_CONFIG` (JSON containing
`systemSettings`/`domainSettings`), `SOGO_TEST_NATIVE_API` and `SOGO_TEST_NATIVE_UI`,
with PostgreSQL 14 and Redis binaries on PATH, then run it with pytest in the
patched source's Nix development environment. It has passed schema validation,
UI runtime/login-page smoke checks, first API startup, restart and a database
restore with a non-superuser application role. All infrastructure/data are isolated
fixtures, not the running pilots or production services.

An isolated NixOS VM also passed actual systemd startup, HTTPS nginx routing,
credential injection/missing-credential refusal, protected key permissions, sandbox
write denial, service restarts, missing-key refusal/recovery, PostgreSQL dump/restore
and a cold boot. Database probe data and key fingerprints survived restoration and
boot; Redis fixture sessions did not. Delayed PostgreSQL role setup verified startup
ordering without API retries. The temporary harness stays outside Foundry at
`/tmp/sogo6-systemd-test`; this does not establish Borg or production browser recovery.

An isolated native browser fixture passed OIDC login, automatic refresh, session-only
logout and fresh-userinfo entitlement denial while introspection remained active.
Task/event/contact edits reached real isolated Radicale resources; stale edits
returned 409 with drafts retained. Successful saves preserved absent task dates,
event instants/alarms, grouped contact labels, partial birthdays and opaque fields.
Native creation and deletion of tasks, contacts and simple timed events also passed,
with independent DAV checks. Collection management and contact-list mutation
controls are gated by server capabilities, and contact exports respect the domain
restriction. New-item pickers and create buttons honor discovered VEVENT/VTODO
support. Native checks confirmed the hidden controls and corrected task default.
These checks used a local OIDC fixture, not Authentik. The temporary setup and
specific evidence/limitations are in `/tmp/sogo6-native-browser/EVIDENCE.md`.

## Before deployment

1. Finish native recurrence/scoped-edit browser checks and review existing resources
   outside the writable subset. Advanced event controls (all-day, participants,
   reminders and recurrence creation) still need to reflect the supported subset.
2. Validate native refresh/revocation and logout navigation against the real provider;
   the local OIDC fixture does not establish that integration.
3. Validate blueprint reconciliation, then ask before deploying. After deployment,
   verify the deployed revision and actual Mail/DAV/OIDC paths without touching
   existing resources or sending another SMTP test message.

No deployment or push has occurred. Existing pilot mail round-trip and live DAV
preservation results remain separate evidence, not substitutes for these gates.

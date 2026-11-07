# Stalwart pilot

The pilot is **Asterope / `lumis.cards` only**, configured for Stalwart **1.0.3**.
Alcyone's Postfix/Dovecot/Radicale mail stack stays unchanged. Its configuration
no longer hosts or relays `lumis.cards`; do not route its mail through Alcyone.
Authentik remains the shared identity provider on Alcyone.

## Configuration

- [Service](../hosts/nixos/asterope/services/stalwart.nix): adapts the upstream
  NixOS module's 0.15 service to the 1.0 binary and JSON datastore configuration.
- [Native API plan](../hosts/nixos/asterope/services/stalwart-plan.nix): applied
  with `stalwart-cli` after startup, using upstream upsert/update operations.
  Exact `{ file = "/path"; }` references become systemd credentials.
- State is persisted at `/var/lib/stalwart`; the 1.0 RocksDB store is `v1/db`.
  The original 0.15 store was not upgraded in place. Vandelay transferred the
  mailbox, identity, active Sieve script, address book and calendar to new state.
- Existing DKIM keys were retained under `v1/keys`, with selectors `202611r`
  and `202611e`. Fresh-host provisioning also needs those keys, not just Nix.
- Each host uses its own `secrets.yaml`. Shared values are duplicated, not read
  from another host's secret file.
- Outbound SMTP binds Asterope's public IPv4/IPv6 addresses and uses Cloudflare
  public DNS, avoiding tailnet split-DNS destinations.
- Email indexing explicitly includes all eight 1.0 fields, including `headers`.
  After changing fields, reindex existing mail with an administrative
  `Task/AccountMaintenance` operation using `maintenanceType: reindex`.

## Access and identity

`mail.lumis.cards` serves SMTP 25/STARTTLS, submission 465/TLS, IMAP 993/TLS,
and HTTPS DAV/JMAP. The backend listens only on `127.0.0.1:8080`.

Management HTTP paths and WebSockets are loopback/tailnet-only. Since 1.0 also
multiplexes management onto `/jmap/`, public requests pass through a small JSON
filter rejecting management capabilities/methods. Its regression tests run in
the Nix build. Ordinary mail JMAP remains public.

Gablogin client `stalwart` uses authorization code + PKCE, with no client secret:

- Issuer: `https://auth.m7.rs/application/o/stalwart/`
- Base scopes: `openid profile email offline_access`
- Mail: `urn:ietf:params:oauth:scope:mail`
- CalDAV: `urn:ietf:params:oauth:scope:calendars`
- CardDAV: `urn:ietf:params:oauth:scope:contacts`
- Registered redirects: `http://localhost:8080`,
  `http://127.0.0.1:8765/callback`, `at.bitfire.davdroid:/oauth2/redirect`

Membership in `lumis-mail` and the administrator-assigned `lumis_mail_account`
attribute select the mailbox through the `mail_account` claim. Gabriel and
Lucky share `contato@lumis.cards`, not login credentials or profile emails.
The mailbox has no password; SMTP advertises only OAuth authentication.

The directory enforces issuer, audience and interoperable scopes. Authentik
copies `nonce` into access JWTs, requiring `allowIdTokenClaims` compatibility;
`unscopedTokens = reject` still rejects its ID tokens, which lack access scopes.
JWT validation is **offline**: revoked tokens may remain usable until their
five-minute expiry. Refresh tokens last thirty days. Neither token expiry nor
revocation terminates an already-authenticated IMAP connection.

## Delivery and remaining pilot work

`contato@lumis.cards` retains mail and forwards copies to Gabriel and Offrakki
through its persistent `lumis-forwarding` Sieve script. Unknown recipients use
the domain catch-all `hi@m7.rs`. MX remains `1 mail.lumis.cards`; the 1.0 migration
required no DNS change.

Protocol checks established PKCE/refresh, both IMAP OAuth mechanisms, migrated
message/header readback, SMTP sender restrictions, DAV CRUD/ETags and private
management ACLs over both public address families. The retained test submission's
RSA and Ed25519 DKIM signatures verify against public DNS. Both contact forwards
and the catch-all received remote SMTP acceptance (the latter after greylisting),
and the delivery queue was empty. This is not owner-client/inbox acceptance or a
complete migration qualification.

Revision `c5fd0384` was deployed and boot-pinned on 2026-11-07, including
persistent header indexing. The disposable OAuth identity and runtime credentials
were removed after validation; refresh revocation rejected reuse, while its issued
access JWT remained usable immediately after revocation (offline validation).

Still to do:

- Exercise the owners' oama/mail/DAV clients, including their exact scopes and
  refresh behavior. DAVx⁵ generic OIDC remains experimental.
- Review the five-minute offline JWT revocation window before expanding the pilot.
- Qualify 1.0 recovery separately. The old encrypted 0.15 archive and restore
  drill do not protect current 1.0 state; no recurring Asterope backup exists.

Do not expand to Alcyone's mail or change other domains as part of this pilot.

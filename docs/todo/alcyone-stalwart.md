# Alcyone mail and DAV migration to Stalwart

**Recommendation: worthwhile, but not ready for a production switch.** Keep
`lumis.cards` on Asterope and plan a separate Stalwart instance on Alcyone for
`m7.rs`, `misterio.me` and `gsfontes.com`. The benefits are shared mail/DAV
administration, JMAP and Gablogin-backed human sign-in. They do not yet outweigh
an unqualified upgrade, untested owner clients and incomplete recovery.

This is a proposal, not an enabled service. No Alcyone DNS, listeners, mailboxes,
Radicale collections, service passwords or routing were changed by this work.
Never use the Vultr API to administer Alcyone. The proposed same-host cutover
needs no MX/address/PTR changes; any other domain's DNS change needs separate
permission.

## Existing contract

| Component | Preserve |
| --- | --- |
| Hostnames | `mail.m7.rs`, sending hostname `alcyone.m7.rs`, `dav.m7.rs` |
| Local domains | `m7.rs`, `misterio.me`, `gsfontes.com` |
| Human mailbox | `hi@m7.rs`, catch-all for all three domains |
| Mail data | `/srv/mail/vmail`, filesystem layout; preserve folders, flags, dates, subscriptions and special-use metadata |
| DKIM | Existing keys under `/srv/mail/dkim`; do not rotate/remove DNS keys as a side effect |
| Service identities | Send-only `auth`, `grafana`, `media`, `firefly`, `calibre` at `m7.rs` |
| Filtering | Postfix/Dovecot/Rspamd today; compare actual spam, forwarding and sender policies, not product feature lists |
| Exposure | Public SMTP 25; submission 465 and IMAP 993 only through `tailscale0`; mail/DAV HTTPS restricted to loopback/tailnet |
| DAV | Radicale on loopback 5232; `/var/lib/radicale/collections`; existing calendar/contact UIDs and collection contents |
| Lumis transit | Explicit `lumis.cards` relay to `155.138.245.163:25`, without DNS loops or local delivery |
| Backups | Existing Borg coverage of `/srv/mail` and Radicale; retain throughout migration |

Observed versions: Postfix 3.11.7 and Dovecot **2.4.5**. Do not paste Dovecot 2.3
master-user/proxy snippets into this installation. Mailbox/collection sizes and
ACLs still need a privileged metadata inventory; they were not read while the
operator was AFK. Never dump password files or message contents into the plan.

Alcyone has about 2 GiB RAM, 837 MiB available and 1.46 GiB swap in use at the
check, with 41 GiB free on `/persist`. Asterope has only about 1 GiB RAM; its
0.15.5 Stalwart used about 151 MiB. These are observations, not a 1.0 capacity
qualification. Measure import, compaction, search and peak concurrent workload
before running two full stacks together on Alcyone.

## Version and configuration gates

- The current upstream NixOS module intentionally runs **0.15.5**. The available
  `stalwart_0_16` is **0.16.27** and explicitly incompatible with that module.
- Upstream **1.0.3**, released 2026-11-04, is the candidate to qualify, not a
  production recommendation merely because it is newest. Avoid migrating
  Alcyone to obsolete 0.15 only to repeat the migration immediately.
- 1.0 uses new bootstrap/configuration objects and management interfaces. Do not
  substitute a new binary under the old TOML-generating module or assume the
  old `/api/` nginx ACL protects every new management endpoint. Prefer updated
  upstream NixOS integration over another Foundry-specific configuration DSL.
- A 1.0 server cannot open a 0.16 store. Upstream `stalwart-migrate` requires
  **0.16.27**, a separate empty 1.0 store, and a final stopped-source pass.
  Asterope is **0.15.5**, not a supported direct source for that tool. Qualify its
  own version-specific migration separately; never open its live DB with 1.0.
- Alcyone starts with an **empty Stalwart store**, importing from Dovecot and
  Radicale. Its path is not a Stalwart schema upgrade. Keep source stores intact.

The unexported [lab package](../../pkgs/stalwart-lab/default.nix) pins the official
x86_64 Linux musl artifact and its SHA-256 from the release API. It built and
reported `1.0.3` locally. It is not selected by `services.stalwart`, exported as
a production overlay, or deployed. Binary attestation verification, full native
NixOS integration and a source-built production package remain gates. See the
[lab/check commands](../../tests/stalwart/README.md).

Published upstream advisories were checked: the nested-MIME OOM advisory
[GHSA-jm95-876q-c9gw](https://github.com/stalwartlabs/stalwart/security/advisories/GHSA-jm95-876q-c9gw)
is fixed in the running 0.15.5. This limited advisory check is not a security
audit or a reason to leave the compatibility guard unmaintained.

## Identity and client gates

Use a separate public native client/issuer and group for Alcyone, provisionally
`stalwart-alcyone` / `personal-mail`, with an administrator-controlled
`alcyone_mail_account: hi@m7.rs` assignment. Do not reuse the Lumis client or
change either owner's profile email or `lumis_mail_account`. A Lumis token must
not authenticate to personal mail, and the converse must fail too.

For 1.0 specifically:

1. Set the exact issuer and explicit `acceptedAudiences`; never disable audience
   validation. Pre-create the mailbox, aliases and service identities before
   accepting mail: OIDC just-in-time creation cannot receive mail before login.
2. Preserve the trusted mailbox claim. New generic clients request `openid`
   plus the interoperable mail/calendar/contact scope URNs, **not necessarily
   `email`**. The current claim mapping only runs with `email`; it is insufficient
   for those clients. Ensure the mailbox claim is released for their scopes and
   reject missing assignments rather than silently falling back to profile email.
3. Create/advertise `urn:ietf:params:oauth:scope:mail`, `:calendars`, `:contacts`
   as needed. Do not work around missing scopes with `unscopedTokens=full`,
   `skipAudienceValidation` or generic UserInfo acceptance.
4. Separate a trusted WebUI client from ordinary mail clients. An installed
   Application's recognized client receives the account's full permissions;
   never make every native mail token first-party or grant the new
   `urn:stalwart:oauth:scope:full` indiscriminately. Keep human app-password/token
   management restrictions unless deliberately reviewed.
5. Test ID-token/access-token distinction, including flows requesting a nonce.
   Do not enable `allowIdTokenClaims` just to make the happy path pass.
6. Review revocation explicitly: 1.0 validates JWT access tokens **offline**;
   its introspection setting is for opaque tokens. Revoking an Authentik JWT
   may leave it usable until expiry, unlike today's per-request guard. Decide
   whether the five-minute window is acceptable; do not claim immediate
   revocation or remove the guard without a replacement test/design. Existing
   authenticated IMAP sessions are a separate issue in either version.
7. Prove native-client registration/discovery rather than equating OAuth support
   with arbitrary-client compatibility. Current Gablogin metadata lacks a
   registration endpoint, `none` in advertised token auth methods, interoperable
   scope URNs and `authorization_response_iss_parameter_supported: true`.
   According to 1.0 docs, its automatic PACC discovery will advertise passwords,
   not OAuth, for such a provider. Manual registered clients can still work;
   do not open unrestricted dynamic registration to silence the warning.
8. Test actual oama/IMAP/SMTP and DAVx⁵ builds with their exact redirects and
   refresh behavior. Stable DAVx⁵ support is not established; its experimental
   PR remains a client qualification task. Test desktop DAV consumers too.

Service senders are **not human SSO users**. Preserve separate least-privilege
SMTP credentials over TLS/tailnet, authorized From addresses, no inbound mailbox
and no management access. Prove coexistence with the OIDC directory on the
chosen version. Do not make Authentik's email delivery depend on obtaining a
working Authentik OAuth session; test recovery/alerts with the IdP unavailable.
A client lacking generic OAuth may need an explicitly approved app credential,
not a silent downgrade of every human account.

## Phases and stop conditions

### 1. Finish the Lumis canary and recovery qualification

- Owner sign-ins, refresh, mail round-trip, shared identity and DAV writes pass
  on their chosen clients. Previous disposable-identity protocol tests are not
  substitutes for these.
- Apply the staged 0.15 header-index field fix in an authorized activation,
  then reindex `contato@lumis.cards`; existing messages need rebuilding too.
  The isolated restore demonstrated exact, bracketed and local-part fixture
  queries working after explicit fields and reindexing, without losing bodies.
- Complete encrypted-archive decryption and independent credential recovery.
  The one-off snapshot/restore check and off-host encrypted copy are evidence,
  not a scheduled backup service. Agree RPO/RTO, retention, destination, alerts
  and restore frequency before adding automation; no periodic Asterope snapshots
  were requested.
- Qualify 1.0 in a lab, then rehearse the *separate* Asterope migration and soak
  on real clients before relying on it as evidence for Alcyone.

### 2. Offline lab and inventory

- Use an isolated VM/network namespace, separate writable state and original
  production stores mounted read-only if needed. Block SMTP egress and scheduled
  forwarding; a restored queue must never replay real mail. Do not run the
  experimental binary against `/var/lib/stalwart` on Asterope.
- Inventory Dovecot mailbox counts/sizes, special-use folders, subscriptions,
  Sieve/ACLs, aliases, DKIM selectors and service sender restrictions. Record
  metadata privately; do not copy decrypted secrets into the repository.
- Inventory Radicale collections and resource UIDs/counts; test events, recurring
  exceptions, all-day/time-zone behavior, tasks and contact groups. Current
  vdirsyncer/khal/khard and mobile behavior must survive, not just a simple VEVENT.
- Import a disposable mailbox/collection first, then a protected source copy.
  Pin and test the selected migration tool (e.g. Vandelay/IMAP migration), its
  Dovecot 2.4 support, deduplication, repeat runs, flags/internal dates and any UID
  changes. Do not assume a generic IMAP copy preserves UIDVALIDITY or threading.
- Use the new management/object API in lab-only plans, with secrets supplied at
  runtime. No blueprint or listener needs enabling on Alcyone yet.

### 3. Parallel production preparation, after explicit approval

- Stage Alcyone Stalwart with **separate** state and loopback/high ports, not
  25/465/993/5232 or existing nginx locations. Leave Postfix/Dovecot/Radicale in
  charge. Prevent accidental outbound delivery during copy/replay tests.
- Provision domains, `hi@m7.rs`, catch-alls and service principals, plus scoped
  credentials. Add its state to Alcyone's snapshot-relative Borg job **before**
  accepting real mail; `/srv/mail` does not cover a new `/var/lib/stalwart`.
- Restore the staged Borg archive in isolation and prove mailbox content,
  attachments, search, DAV, DKIM, aliases and credentials. Account exports alone
  do not restore domain keys, principals, active Sieve or the queue.
- Initial mail copy and repeated incremental catch-up may run while Dovecot is
  serving. A temporary Dovecot master credential, if the tool needs it, is a
  high-privilege secret: bind access narrowly, use 2.4 syntax, and remove it.
- Keep original collection data immutable for the final copy. Plan a clean
  vdirsyncer/DAVx⁵ re-discovery/new client account rather than reusing stale sync
  tokens against a different collection layout. Run `vdirsyncer discover` before
  committing new collection IDs, and preserve local exports during resync.

### 4. Explicit maintenance window

1. Take verified source backups and record both known-good NixOS generations.
2. Stop source client writes/hold inbound mail; run the final incremental mail
   copy and final DAV export/import. This is **not** promised to be zero downtime.
3. Switch ownership of the existing ports to Stalwart and update only the
   necessary local nginx/autoconfig targets. Preserve tailnet-only submission,
   IMAP and DAV; do not copy Asterope's public-port policy blindly.
4. Preserve/import existing DKIM identities and prove outbound SPF/DKIM/DMARC,
   forwarded-message behavior and ARC/SRS where applicable. Keep the Lumis relay
   explicitly pointed at Asterope, with no mutual default-route loop.
5. Test external inbound/outbound, all catch-alls, no open relay, sender
   impersonation rejection, service SMTP and IdP-outage behavior. Test owner
   refresh/revocation, both IMAP mechanisms, search/body readback and DAV CRUD
   with conditional writes. Verify management remains private on the **actual
   new API paths** and that backups contain the now-active store.
6. Resume writes/queues, monitor delivery/spam/latency and retain the original
   data and service declarations throughout an agreed rollback window. Remove
   old services/secrets only after acceptance and a fresh successful restore.

### Rollback

Stop new writes and hold mail first. Restore the known-good NixOS generation,
ports and nginx routes. **Do not simply start the old stack and discard mail or
DAV changes accepted by Stalwart:** export/reconcile the delta while preserving
both stores, then resume source delivery. Keep original DKIM keys, service
credentials and encrypted source backups until the rollback window closes.
A same-host protocol cutover needs no MX rollback; the existing Lumis transport
must remain valid in either stack. Rehearse this recovery before the window.

## Immediate safe preparation already available

- Reusable public checks and a root-only, capped-resource, isolated 0.15 restore
  probe under [`tests/stalwart`](../../tests/stalwart/README.md).
- Staged Nix header-index workaround, not activated on Asterope.
- Hash-pinned 1.0.3 lab binary, built locally, not wired into any host.
- An encrypted off-host mail-state copy and limited restore evidence documented
  in [backups](../backups.md). No scheduled jobs or production service changes.

## References

Upstream documentation is rolling and describes 1.0, **not** the running 0.15.5:

- [1.0.3 release and binary attestation](https://github.com/stalwartlabs/stalwart/releases/tag/v1.0.3)
- [External OIDC behavior and compatibility](https://stalw.art/docs/auth/backend/oidc/)
- [Request authentication](https://stalw.art/docs/auth/authentication/)
- [0.16.27 to 1.0 migration requirements](https://stalw.art/docs/migration/upgrade-0-16/)
- [Dovecot/Postfix migration preparation](https://stalw.art/docs/migration/guide/configure-source/dovecot-postfix/)
- [Backup consistency and restores](https://stalw.art/docs/management/maintenance/backup/)

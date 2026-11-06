# Stalwart mail and DAV on Asterope

**`lumis.cards` MX points to `mail.lumis.cards`, priority 1, TTL 300.** The cutover
was authorized and completed on 2026-11-06, preserving contact forwards and the
catch-all. Other mail domains remain on Alcyone. Never modify Alcyone through
the Vultr API or change another domain's DNS.

## Access and state

- Public hostname: `mail.lumis.cards`.
- Asterope: `155.138.245.163`, `2001:19f0:6401:cf2::1`.
- Tailnet: `100.77.0.11`, `fd7a:115c:a1e0:77::b`.
- SMTP ingress: 25 with STARTTLS; authenticated submission: 465 with TLS.
- IMAP: 993 with TLS; DAV and JMAP: HTTPS.
- Management `/api/`: loopback/tailnet only. The backend is loopback port 8080.
- State: `/var/lib/stalwart`, persisted under `/persist`. A one-off encrypted
  off-host copy and isolated data-restore check now exist; recurring backups and
  independent key recovery remain unfinished. No periodic snapshots were added.

The fallback `admin` credential is an administrative/bootstrap escape hatch,
not an end-user mail password. Do not put decrypted secrets in commands, logs,
chat, or the Nix store. The unused encrypted `contato-password` from the initial
bootstrap is not installed as a mailbox credential.

The host uses upstream `services.stalwart.settings` and `.credentials`. Local
helpers collect exact `{ file = "/absolute/path"; }` leaves recursively, deduplicate
paths, and substitute systemd credential references. There is no extra Stalwart
module or `declarative` namespace.

Stalwart's database also holds generated defaults, principals, and DKIM keys.
Do not set `config.local-keys = ["*"]`: that hides database settings and makes
initialization try to write defaults into the read-only Nix configuration.
SMTP resolution deliberately uses public DNS rather than tailnet split DNS;
outbound connections bind the two public addresses with matching SPF/PTR.

## Gablogin authorization

The blueprint is `hosts/nixos/alcyone/services/authentik/stalwart.yaml`:

- Public native client: `stalwart`, authorization code with PKCE and refresh.
- Confidential introspection resource: `stalwart-resource`. The **issuing native
  provider** lists this resource in `jwt_federation_providers`, permitting it to
  introspect native tokens; setting the relationship in reverse does not work.
  Its shared secret is encrypted to both hosts in
  `hosts/nixos/asterope/oidc-secrets.yaml`.
- Application access requires membership in **`lumis-mail`**, not the broad
  `users` group.
- A trusted administrator must assign `attributes.lumis_mail_account`, e.g.
  `contato@lumis.cards`. The mailbox name is independent of the user's Gablogin
  username and profile email. Do not expose this assignment as a user-editable
  enrollment/profile field.
- The provider's additional `email` scope mapping supplies `mail_account`.
  Standard OAuth clients need no custom scope name.

Gablogin users **`gabriel`** (`gabriel@gsfontes.com`) and **`lucky`**
(`offrakki@gmail.com`) are members of `lumis-mail`, both assigned
`lumis_mail_account: contato@lumis.cards`. They share one Stalwart mailbox and
its DAV collections, without sharing Gablogin credentials or changing their
profile email addresses. These assignments are persistent Authentik data.

Client parameters:

| Parameter | Value |
| --- | --- |
| Issuer | `https://auth.m7.rs/application/o/stalwart/` |
| Discovery | issuer + `.well-known/openid-configuration` |
| Client ID | `stalwart` |
| Client secret | none; public PKCE client |
| Scopes | `openid profile email offline_access` |
| oama redirect | `http://localhost:8080` (configure this fixed redirect) |
| Test redirect | `http://127.0.0.1:8765/callback` |
| DAVx⁵ redirect | `at.bitfire.davdroid:/oauth2/redirect` |

Access tokens last five minutes; refresh tokens last thirty days. Use
XOAUTH2/OAUTHBEARER for SMTP/IMAP and `Authorization: Bearer` for DAV/JMAP.
Provisioned mailboxes deny `manage-passwords` and `authenticate-oauth`, preventing
app-password creation and minting independent Stalwart tokens through the account
API. The latter permission controls Stalwart's own authorization endpoint, not
external bearer authentication. SMTP advertises only OAuth mechanisms. IMAP 0.15
still advertises PLAIN; the mailbox has no password/app-password credential to
use with it. This is not a claim that PLAIN has been globally removed, and the
administrative escape hatch described above is separate.

### Why the introspection guard exists

The NixOS module currently supports Stalwart **0.15.5**, not the differently
configured 0.16 package. The 0.15 OIDC backend maps fields from introspection
without checking `active`, client, or scope. Authentik also introspects refresh
tokens. The loopback `stalwart-introspection` service therefore:

- authenticates confidentially to Authentik's introspection endpoint;
- accepts only active, unexpired access tokens for the dedicated issuer/client,
  expected audience, `email` scope, and an ASCII `@lumis.cards` mailbox;
- rejects opaque refresh tokens and fails closed on provider errors;
- strips identity claims from rejected responses and never logs tokens;
- returns HTTP 401 for rejected tokens: Stalwart interprets HTTP 200 without a
  mailbox claim as a transient backend fault, otherwise producing SMTP 454
  instead of the appropriate 535 authentication failure.

The 0.15 HTTP authentication cache also has an inverted expiry comparison, so
this canary disables that cache. Live revocation tests rejected subsequent HTTP
requests and new SMTP/IMAP logins. This does not terminate an already-authenticated
IMAP connection. Remove this compatibility layer only after verifying native
replacement behavior.

Guard regression tests (no credentials/network required):

```sh
python3 -B hosts/nixos/asterope/services/test_introspection.py
```

### DAVx⁵

Generic OIDC is experimental in
[PR #2585](https://github.com/bitfireAT/davx5-ose/pull/2585), not assumed available
in the installed stable client. In a build containing that PR, use
`https://mail.lumis.cards/dav/cal`, client `stalwart`, and explicitly include
`offline_access` in the editable scope field. No APK has been built/tested here.
Debug/application-ID variants need their own exact redirect registration.

The DAV 401 challenge advertises RFC 9728 resource metadata, which points to
Gablogin. Root OIDC/OAuth discovery also redirects there rather than advertising
Stalwart's separate built-in issuer. Protocol-level DAV discovery, collection
creation, event/contact read-write, refresh, and revocation passed with real
Gablogin tokens; this does not establish compatibility with an untested APK.

## Principal and signing bootstrap

Principals and DKIM keys are persistent API-managed state, not recreated from
Nix settings. Stalwart 0.15 can return HTTP 200 with a JSON `error`; always check
the JSON envelope, not only the HTTP status.

Authenticated administrative API calls over loopback/tailnet:

1. `POST /api/principal/deploy` with `{"type":"domain","name":"lumis.cards"}`.
2. Provision each mailbox with the same endpoint, for example:

   ```json
   {
     "type": "individual",
     "name": "contato@lumis.cards",
     "emails": ["contato@lumis.cards"],
     "roles": ["user"],
     "disabledPermissions": ["manage-passwords", "authenticate-oauth"]
   }
   ```

3. `POST /api/dkim` once for each algorithm, using
   `{"algorithm":"Rsa","domain":"lumis.cards"}` and
   `{"algorithm":"Ed25519","domain":"lumis.cards"}`. Check for existing keys
   first; never print a duplicate-key error that might include private material.
4. Reload with `GET /api/reload`; inspect only errors/warnings, not secret values.
5. `GET /api/dns/records/lumis.cards` gives public record proposals, not permission
   to apply all of them indiscriminately.

The canary has `contato@lumis.cards` without a mailbox password. The disposable
`validation@lumis.cards` mailbox and temporary Authentik test user/provider were
removed after validation. DKIM selectors are `202611r` and `202611e`. They are
published; SPF additionally permits Asterope while retaining every old source.
Both Asterope PTRs point to `mail.lumis.cards`. The MX now points there too.

## Routing and rollback

- `contato@lumis.cards` stores mail locally and forwards copies to
  `gabriel@gsfontes.com` and `offrakki@gmail.com`. The active personal Sieve script
  is `lumis-forwarding`, seeded from
  `hosts/nixos/asterope/services/lumis-forwarding.sieve` through JMAP. It is
  persistent API-managed state, not automatically overwritten by Nix. Merge any
  later user rules rather than replacing them. The Sieve runtime redirect limit
  and advertised maximum are both two.
- The `lumis-catchall` list principal has `emails: ["@lumis.cards"]` and
  `externalMembers: ["hi@m7.rs"]`, preserving delivery of unknown addresses.
- Alcyone no longer treats `lumis.cards` as a local mailbox/alias domain. Its
  Postfix `relay_domains` includes it, with transport
  `lumis.cards smtp:[155.138.245.163]:25`. This handles locally submitted mail and
  senders still using the old MX without looping through public MX resolution.
  The old mailbox data was retained; it was not migrated or deleted.
- Alcyone's corrected Authentik blueprint and relay configuration were deployed
  and pinned for boot. Asterope's forwarding limits were deployed and pinned too.
- Both Vultr authoritative nameservers and public Cloudflare/Google resolvers
  returned the new MX after the update. No other DNS records changed during
  this cutover; previous SPF sources remain permitted while old queues drain.

Before an MX rollback, restore Alcyone's previous local domain, forwards,
catch-all, and mailbox configuration and remove its Asterope relay transport.
Then restore `MX 1 mail.m7.rs` with TTL 300. Changing DNS alone would still relay
mail to Asterope. Keep Asterope's stored mail intact and reconcile any mail it
received during the cutover. The pre-update DNS records were saved locally in
`/run/user/1000/asterope-lumis-dns-cutover-before.json`.

## Validation and follow-up

Live checks on 2026-11-06 established:

- Verified TLS, anonymous inbound delivery to the disposable validation mailbox,
  rejection of unauthenticated relay/submission, and private management ACLs
  including spoofed-forwarding-header rejection.
- Browser-based Gablogin authorization-code/PKCE login and refresh grants, with
  the administrator-assigned mailbox claim rather than the profile email.
- Actual bearer JMAP, SMTP XOAUTH2 submission, IMAP XOAUTH2 and OAUTHBEARER login,
  and IMAP body readback of the submitted synthetic message. The external copy
  reached `hi@m7.rs` with SPF, RSA and Ed25519 DKIM, and DMARC passing.
- CalDAV and CardDAV discovery, temporary collection creation, resource creation,
  reads, conditional updates using ETags, and deletion. Temporary collections
  were removed afterward.
- Cross-mailbox JMAP/DAV access and unauthorized sender addresses were rejected.
  The non-admin validation user could not change its mailbox assignment through
  Authentik's user-update API (permission-denied 403).
- Active wrong-client and missing-email-scope tokens were rejected, as were an
  expired access token and an active opaque refresh token used as a bearer token.
- Access-token revocation immediately rejected subsequent DAV requests (401),
  new IMAP logins, and new SMTP logins (535). Revoking a refresh token made the
  next refresh grant fail with `invalid_grant`.

The temporary Authentik user, application, provider, binding, and Stalwart
validation mailbox were deleted. The guard's eight regression tests also run
as part of its Nix build. These tests do not replace signing in as each actual
owner with their chosen clients.

Known canary issue, now diagnosed: 0.15.5's default empty email search-field set
indexes other fields but skips headers. Explicitly selecting **all twelve email
fields**, not just headers, and reindexing fixed Message-ID queries against an
isolated snapshot copy, including bracketed and local-part fixture searches.
The workaround is staged in `services/stalwart.nix` but **not activated**; rebuild
existing indexes after deployment with authenticated loopback
`GET /api/store/reindex/email/contato%40lumis.cards`. Production header search
remains an acceptance item until then. See [the restore check](../tests/stalwart/README.md).

Cutover checks additionally established:

- Alcyone relayed synthetic contact and unknown-recipient messages to Asterope.
  The contact copy remained in its local INBOX, both Sieve forwards received SMTP
  250 acceptance, and the catch-all and Gabriel's forwarded copy reached
  `hi@m7.rs` INBOX without looping.
- After the MX change, another synthetic message delivered through Asterope's
  public SMTP address was retained locally and forwarded, with an empty queue
  afterward. Alcyone verified SPF, both DKIM signatures, and DMARC on its copy.
- Public IPv4 and IPv6 SMTP STARTTLS certificates verified; contact and catch-all
  recipients were accepted on both, while unrelated external relay was rejected
  with 550. Gablogin discovery remained available after Alcyone's deployment.

The subsequent AFK check verified public DNS, TLS/protocol exposure and ACLs,
plus an isolated crash-consistent restore of the mail database. Fresh browser
login/refresh/revocation was **not repeated**: the disposable identity/tokens were
already removed, and obtaining new credentials required interaction. Previous
real-token results above remain valid historical evidence, not a claim of a new
owner-client sign-in. The reusable [public check](../tests/stalwart/README.md)
delivers no mail by default.

Outstanding follow-up, accepted as unfinished when authorizing the MX cutover:

1. Test the actual owners' clients, activate/reindex the staged header fix,
   and validate oama/DAVx⁵ integration rather than assuming protocol success
   proves a particular client build works.
2. Finish durable mail backup/restore and independent key recovery. The one-off
   encrypted copy and limited restore evidence are in [backups](backups.md);
   there is no recurring Asterope backup or requested periodic snapshot schedule.
3. Restore the operator's client/tailnet access when present. Atlas still lacked
   Asterope in its peer map and reported itself offline; Asterope saw Atlas as
   offline too. Direct tailnet probes timed out. No network restart/reauthentication
   was attempted while AFK.
4. Publish the configuration through the normal signed-commit/CI path when
   authorized; this cutover was deployed directly. Keep old SPF sources until
   old queues and forwarding have drained.

The [Alcyone migration proposal](todo/alcyone-stalwart.md) recommends a separate,
qualified 1.0 instance there, not copying this 0.15 compatibility deployment or
switching the remaining domains now. Its lab package is not wired into a host.

Do not push this change without explicit permission.

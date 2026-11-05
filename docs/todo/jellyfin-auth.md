# Jellyfin → Gablogin

Jellyfin-side implementation lives in
`hosts/nixos/merope/services/media/jellyfin.nix`; the Authentik provider is in
`hosts/nixos/alcyone/services/authentik/jellyfin.yaml`. No extra Jellyfin feature
options or staging switches are used.

## Current state (2026-11-05)

- The operator provisioned the shared client secret, backed up Jellyfin and
  deployed both hosts. They verified an ordinary account's OIDC login preserved
  its ID and permissions, non-member denial, binding persistence across restart,
  and the former local administrator's login before its conversion.
- The administrative batch then converted the remaining seven authentication
  providers and durably installed eight explicit subject-to-user-ID bindings.
  All other user fields, permissions and preferences were checked unchanged.
  No users were created, deleted, renamed, enabled or promoted.
- Jellyfin `admin` is bound to Authentik `akadmin`, not `gabriel`. The latter keeps
  its separate existing account. `akadmin` was added to `jellyfin-access`; its
  confirmed TOTP and WebAuthn devices were retained. A fresh browser login as
  `akadmin` and access to the Jellyfin admin dashboard still need operator testing.
- There is no remaining local-password authentication provider. Old password
  hashes were not erased, but the OIDC provider rejects username/password login.
  Existing client sessions and API keys were not revoked.
- Jellyfin restarted successfully and its public `/health` endpoint returned
  `Healthy`. The initial probe encountered the startup response before startup
  finished; the migration itself had committed successfully and was not rerun.
- A stopped-service SQLite backup and matching pre-cutover identity map are at
  `/persist/var/backup/jellyfin-oidc/20261105T034427.226474Z` on Merope, protected
  for root access. Restore the database and map consistently, not independently.

The source configuration now disables username migration and hides the web
password form, user picker and password-reset control, preserving the Gablogin
button and native Quick Connect. **Deploy the updated Merope configuration to
apply these final UI/configuration changes**; the live account bindings above
have already been applied independently of deployment. The generated Jellyfin
unit built successfully; fixture checks covered nine startup-guard cases and
idempotent branding updates that preserve existing HTML/CSS.

## Security and authorization decisions

- Build `aussierk/jellyfin-plugin-oidc` 2.1.0.1 from hash-pinned source with
  locked NuGet dependencies and the local device-code patch. This replaces the
  previously pinned release ZIP; no binary equivalence to that ZIP is claimed.
  The running Jellyfin version is 12.4.0.
- Use Authentik's hashed user ID as `sub`, asymmetric signing, authorization code
  with plugin-managed PKCE, an exact callback and pinned discovery endpoints.
  Both the Authentik application and plugin require `jellyfin-access`.
- No account creation, email linking, display-name changes or avatar sync.
  Username migration is closed after explicit administrative prebinding.
- Policy/library management deliberately remains **off**. Existing per-user
  Jellyfin permissions are authoritative; guessed group roles must not overwrite
  library restrictions or administrator status. The admission group remains
  independently enforced. Empty role mappings are not an additional gate here.
- The startup guard rejects local authentication providers and corrupt,
  conflicting, incomplete or missing established OIDC bindings. The identity map
  is persisted at `/var/lib/jellyfin/plugins/configurations/` alongside plugin
  configuration. This mitigates fail-open recovery at startup, not every possible
  upstream ownership bug. Back up and restore it with the matching user database.
- Hiding the web form is cosmetic; the actual password-authentication rejection
  comes from every user's OIDC authentication provider. Native clients use
  Quick Connect. A fully automatic redirect from the web client's login route
  is not implemented; it is a browser-side hash route, not an nginx location.

## Device sign-in instructions

The server-served web client labels Quick Connect as **Entrar com outro
dispositivo** and tells users to visit `https://media.m7.rs/connect` and enter
their displayed code. The shortcut replaces `/quickconnect` and redirects to
`/sso/OIDC/QuickConnect/authentik`, preserving the query string. Authenticate
with Gablogin, then explicitly approve the code.

The locally patched plugin also accepts an optional `user_code` query parameter:

```
https://media.m7.rs/connect?user_code=012345
```

This is suitable for a QR containing the approval URL and public device code,
**never** the device's polling secret or a Jellyfin/OIDC token. Only one value
of exactly six ASCII digits is accepted; empty, repeated, oversized and malformed
values return HTTP 400 before starting OIDC. Leading zeroes survive. Omitting
`user_code` retains manual entry.

The code travels in browser-bound server-side OIDC state, not the IdP request or
callback URL. The approval page prefills it from a safely serialized JSON data
island and still requires an explicit **Authorize** click. A callback query
parameter cannot substitute a different code. Existing CSRF, nonce, PKCE,
admission checks and state expiry remain in place. An expired or incorrect device
code can be edited and retried using the existing approval form.

The two web-client strings are customized in Brazilian Portuguese and the default
English catalog; other locales are unchanged. A web rebuild produces new asset
content hashes. This affects browsers and clients using the server's web UI,
not Findroid's native interface or clients bundling their own web assets.

The server-served web client's device-code dialog includes a locally generated,
clickable QR carrying the public code. Beneath it, a single fallback instruction
reads **Ou visite https://media.m7.rs/connect e digite {code}**; there is no
separate caption or visible approval URL containing the code. The QR library is hash-pinned and bundled at
build time; no external image-generation service receives the URL or code. The
existing polling secret is used only by the normal device polling/login flow,
never passed to the QR renderer. Invalid codes produce no QR. The generated SVG
includes a white background and four-module quiet zone for scanning in dark mode.

Fourteen QR helper tests pass, and decoding a rendered test QR recovered exactly
`https://media.m7.rs/connect?user_code=012345`. The helper tests also run before
the web production build in CI. The full patched web bundle and real-device scan
still need CI/deployment verification; this does not alter native client screens.

The patched plugin built and all 589 tests passed, including URL validation,
leading zeroes, optional manual entry, OIDC round-trip and callback-tampering
cases. The package retains the existing flat DLL/metadata layout. Full web/host
builds remain for CI. After deploying Merope, verify the `/connect` redirect,
actual Gablogin/MFA round-trip, explicit approval, expired-code retry and native
app handoff with a real requesting device.

## Logout and revocation

The Authentik Blueprint configures the plugin's native signed back-channel
endpoint, `https://media.m7.rs/sso/OIDC/BackchannelLogout/authentik`, using
`logout_method: backchannel`. Deploy Alcyone to apply it; changing this Blueprint
alone does not modify the running provider. No custom revocation bridge is used.

Jellyfin's own Logout currently ends its local session but leaves Gablogin signed
in, as confirmed by the operator. The plugin has no RP-initiated logout endpoint
or web Logout-button integration. Its session-ended consumer only prunes tracking.
A future browser integration must finish Jellyfin logout before navigating to
`https://auth.m7.rs/application/o/jellyfin/end-session/`; a redirect returned to
an API fetch is not enough. This button change is not implemented here.

Native back-channel support is not a reliable general revocation guarantee yet:

- Authentik 2026.8.5 selects **unexpired access tokens** when dispatching logout on
  session deletion. Jellyfin's ten-minute token is not refreshed by the plugin;
  after expiry, the session-deletion path can send no notification at all. Merely
  extending token validity would mask this lifecycle problem, not solve it.
- The plugin tracks browser sessions in memory. After restart, its persisted
  identity-map fallback can revoke **all** of a user's Jellyfin tokens instead of
  just the originating IdP session. A `sid`-only notification for an older session
  may instead match nothing and return 200. Quick Connect also lacks the browser
  session's in-memory correlation, so do not assume device-scoped revocation.
- Removing an admission group is not itself a logout notification. Existing
  Jellyfin sessions and API keys remain independent of the IdP access-token TTL.

After deployment, test with two independent IdP/browser sessions for the same
user, preserving the second session as a scoping control:

1. Within ten minutes of fresh OIDC login, delete only the first Authentik session.
   Confirm delivery in Authentik's worker logs and `decision=backchannel-logout`
   with a nonzero revocation count in Jellyfin's logs. Check an authenticated API
   request from the first browser is denied; a cached page or HTTP 200 callback
   alone does not prove revocation. The second browser should retain access.
2. Repeat with a fresh login allowed to age beyond ten minutes without another
   OIDC login. Record whether any notification is sent and whether access survives.
3. Repeat after a Jellyfin restart, checking both browsers to expose any fallback
   widening. Test Quick Connect separately. These are deliberate logout tests:
   use sessions whose revocation is acceptable, not other users' active devices.

The updated Blueprint package built successfully, and the live plugin endpoint
returned HTTP 400 for both missing and malformed logout tokens. Those negative
checks do not exercise a valid signed logout or prove session revocation. Do not
claim the acceptance matrix passed until tested against the deployed provider.
Token-expiry and restart behavior above are source-reviewed limitations, not
live-test results.

Upstream references: [plugin architecture](https://github.com/aussierk/jellyfin-plugin-oidc/blob/v2.1.0.1/ARCHITECTURE.md),
[plugin limitations](https://github.com/aussierk/jellyfin-plugin-oidc/blob/v2.1.0.1/SECURITY.md),
and [Authentik session-deletion signal](https://github.com/goauthentik/authentik/blob/version/2026.8.5/authentik/providers/oauth2/signals.py).

## Remaining acceptance checks

1. Sign in using **akadmin** through Gablogin and verify the original Jellyfin
   `admin` account and admin dashboard access. `gabriel` remains a separate account.
2. Deploy the final Merope configuration. In a clean browser session, verify only
   Gablogin/Quick Connect remain as login choices, and the old admin password
   cannot authenticate through the API or a native client.
3. Deploy Alcyone's back-channel configuration and run the logout/revocation
   matrix above. Test Quick Connect/TV playback and an IdP outage. For immediate
   removal, disable the Jellyfin account and revoke its sessions explicitly.
   Confirm normal backups include the new complete identity map.

## Recovery without a local administrator

Recovery is independent SSH/root access, the persisted database/map and their
backups, plus the declarative configuration. There is no retained password-based
Jellyfin recovery account. To deliberately restore local access, stop Jellyfin,
relax the OIDC-only startup guard and restore the intended account's local
provider under controlled administrative access; also restore the web controls
if needed. A Nix rollback alone does not revert database authentication providers.
Avoid restoring an old entire database merely to change one account's login
method, since that would discard newer application data.

The upstream UserInfo subject-validation, provider-scoping and logout findings
from the supplied audit remain unfixed. ID-token claim inclusion and one provider
reduce exposure but do not replace those fixes. No reliable back-channel logout
or immediate IdP-driven revocation is claimed by this integration.

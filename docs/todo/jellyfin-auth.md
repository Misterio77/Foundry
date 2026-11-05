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

- Pin the reviewed `aussierk/jellyfin-plugin-oidc` 2.1.0.1 release ZIP by hash.
  This does not establish that its DLLs reproduce from reviewed source. The
  running Jellyfin version is 12.4.0.
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

## Remaining acceptance checks

1. Sign in using **akadmin** through Gablogin and verify the original Jellyfin
   `admin` account and admin dashboard access. `gabriel` remains a separate account.
2. Deploy the final Merope configuration. In a clean browser session, verify only
   Gablogin/Quick Connect remain as login choices, and the old admin password
   cannot authenticate through the API or a native client.
3. Test Quick Connect/TV playback, logout and an IdP outage. Authentik group
   removal does not promise immediate revocation of existing Jellyfin sessions;
   disable the Jellyfin account and revoke sessions when immediate removal is
   required. Confirm normal backups include the new complete identity map.

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

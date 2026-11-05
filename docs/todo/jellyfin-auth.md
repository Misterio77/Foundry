# Jellyfin → Gablogin cutover

Implementation is in `hosts/nixos/merope/services/media/jellyfin.nix`, with the
Authentik provider in `hosts/nixos/alcyone/services/authentik/jellyfin.yaml`.
There are no new Jellyfin feature options or staging switches. This is prepared
configuration, not a claim that accounts have already migrated.

## Decisions

- Pin `aussierk/jellyfin-plugin-oidc` 2.1.0.1, the version audited by the operator's
  other agent. The release ZIP is hash-pinned; this does not establish that its
  DLLs reproduce from reviewed source. The public server reports Jellyfin 12.4.0.
- Use Authentik's hashed user ID as `sub`, asymmetric signing, authorization code
  with PKCE, exact callback and pinned discovery endpoints. The plugin performs
  PKCE itself. Both the Authentik app and plugin require `jellyfin-access`.
- Do not create accounts, link by email, rename users or synchronize avatars.
  Existing Jellyfin IDs, permissions, library restrictions and history stay put.
- Deliberately leave policy/library management **off**: this is an authentication
  cutover, not a replacement of existing per-user authorization with guessed
  group roles. Admission remains enforced independently. Empty role mappings are
  not an additional gate in this mode; the dedicated access group is essential.
- The operator approved username-based first-time migration because they create
  all Authentik accounts and have mapped their ownership. `MigrateLocalUsers` is
  temporarily true for that cutover, not a permanent account-linking mechanism.
  Freeze account creation/renaming until it is turned off.
- The plugin refuses username-only migration of administrators. Keep the current
  local admin for independent recovery; do not weaken that check. Migrating the
  main admin requires a separate retained local administrator and an explicit
  hashed-subject → Jellyfin-ID binding before changing its authentication provider.
- A startup guard rejects corrupt, conflicting or incomplete identity maps and
  refuses to start if an established OIDC user has no binding. This mitigates
  fail-open recovery after a restart; it does not fix the upstream implementation
  or replace a tested backup. The JSON map lives alongside plugin configuration
  under the already persisted `/var/lib/jellyfin/plugins/configurations`.
- The existing web password form remains available for local recovery. Migrated
  accounts switch to the plugin's authentication provider; hiding the web form
  would not itself disable password authentication. Native clients should be
  verified through Quick Connect. Existing client sessions are not revoked by
  merely changing how future logins authenticate.

## Batched operator actions

1. Privately generate one new single-line client secret and add the **same value**
   as `authentik-jellyfin-client-secret` to both Alcyone's and Merope's SOPS files.
   No secret was generated, read or placed in the Nix store by this preparation.
2. Take a consistent Jellyfin database/configuration backup. Include
   `Jellyfin.Plugin.OIDC.UserProviderMap.json` once created; restore it with the
   matching database. Do not install another copy of this plugin via the catalog.
3. Deploy Alcyone first, verify `Foundry - Jellyfin` applied, then add only the
   approved existing accounts to `jellyfin-access`. Compare exact usernames;
   account creation alone is not evidence that their spellings match.
4. Check discovery against the pinned issuer, authorization/token/userinfo URLs
   and per-provider JWKS URL. Deploy Merope in the same coordinated cutover.
   Confirm Jellyfin trusts nginx's loopback forwarding so the callback CSRF cookie
   is Secure. No extra staging flag needs enabling.
5. Ordinary existing accounts migrate at their first successful OIDC login.
   Verify their original user IDs and policies before/after, including restricted
   libraries and viewing history. An administrative prebinding batch is still
   needed if migration must finish without each user's login; do not claim that
   installing the plugin already performed it.
6. Once the approved accounts are bound, set `<MigrateLocalUsers>false</MigrateLocalUsers>`
   in the Nix-owned XML and redeploy. Verify a new identity or recycled username
   cannot acquire an established account. Test denial for a non-member, a
   disabled Jellyfin account, mismatched identities and an IdP outage.
7. Test browser login, Quick Connect/TV playback, local recovery-admin login and
   logout. Group removal does not promise immediate revocation of existing
   Jellyfin sessions: disable the Jellyfin account and revoke its sessions when
   immediate removal is required.

The upstream UserInfo `sub` validation, provider-scoping and logout findings in
the supplied audit remain unfixed. ID-token claim inclusion and one provider
reduce exposure but are not substitutes for those fixes. No back-channel logout
is advertised as reliable by this configuration. No sudo, deployment, credential
rotation or live user modification has been performed during preparation.

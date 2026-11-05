# Seerr OIDC follow-up patches (draft)

Target: `~/Projects/Personal/seerr`, after the declarative-mode work finishes.
This is an implementation brief, not an applied patch. Keep the two changes
independently reviewable. No changes to that working tree are required to draft
or review this plan.

## 1. Email-optional OIDC accounts

Identity remains `(provider slug, OIDC sub)`. Email and username are profile
attributes, never grounds for automatically linking two identities.

### Storage and signup

- Make `User.email` explicitly nullable (`string | null`), retaining uniqueness
  for non-null values. SQLite and PostgreSQL permit multiple NULLs in a unique
  column. Use an explicit column type so TypeORM does not infer `Object` from
  the union type.
- Fix both directions of the email transformer: preserve NULL instead of
  converting it to an empty string. Normalize absent/blank email to NULL;
  normalize supplied emails by trimming and lowercasing.
- Add the appropriate database migration for both supported backends. Preserve
  existing non-empty values; do not guess which legacy values are real emails
  or overwrite existing accounts. Empty strings can become NULL.
- In `server/routes/auth.ts`, allow creation whenever `newUserLogin` is true,
  even without `fullUserInfo.email`. Check email collisions only for a non-null
  normalized email; continue rejecting collisions instead of auto-linking.
- Use a non-blank `preferred_username` as the username when available. Fall back
  to a stable provider/subject-based label, not a fabricated email. Username
  collisions must not merge identities; usernames are display attributes.
- Always populate `LinkedAccount.username`, including when neither email nor
  preferred username exists. OIDC subject remains the authoritative key.
- Remove the missing-email rejection from this signup path. Disabled signup
  must still reject an unknown identity. Missing/invalid permission claims must
  still fail closed before any user is created.
- For accounts without email, use a bundled local default avatar rather than
  hashing an invented email or making an unnecessary Gravatar request. Preserve
  a valid supplied picture. Absolute avatar URL handling is a separate concern.

### Consumers and declarative integration

- Make the declarative owner's email optional, normalizing omission to NULL;
  keep `owner.provider`, `owner.subject`, and `owner.username` authoritative.
  Adjust bootstrap/provisioning and tests without weakening the owner-subject
  guard or changing user 1 based on email.
- Audit API/OpenAPI types, user/profile forms, search, display-name fallback,
  logging, Gravatar calls, notification agents, password generation/recovery,
  and user creation/update routes for the nullable value.
- OIDC profile editing must tolerate no email. Do not expand this change into
  allowing email-less local-password signup: that flow may keep requiring it.
- Email delivery must skip users without an address, including explicitly
  addressed notification paths. Password reset must not query `email IS NULL`
  from an empty input or select an arbitrary email-less account. Preserve
  non-enumerating reset responses.
- No dummy `.invalid` addresses, shared empty-string identities, or implicit
  changes to existing users' permissions. Do not send email just because an
  OIDC account was created.
- Keep ordinary profile synchronization out of scope: whether login updates an
  existing email/username is a separate decision with collision semantics.

### Acceptance tests

1. Two different subjects without email can sign up and log back into their
   respective accounts; no duplicate users appear.
2. Missing, NULL, empty, and whitespace-only email normalize consistently.
3. Signup without preferred username still creates a usable display/link name.
4. A supplied mixed-case email is normalized; an existing-email collision
   rejects without linking or mutating that account.
5. Two subjects with the same preferred username remain distinct identities.
6. Disabled signup and invalid permissions still reject without creating users.
7. Email-less owner bootstrap works and retains declarative identity pinning.
8. Migration preserves IDs, requests, linked accounts, and non-empty emails on
   SQLite and PostgreSQL; multiple NULL emails satisfy the unique constraint.
9. Profile UI/API work with NULL email; notification/reset paths neither crash
   nor send to a placeholder recipient.

### Foundry rollout

After the application patch is deployed, switch **only Seerr** from
`foundry-provider-authorization-email-required` to an authorization flow without
an email prompt. Keep other applications' requirements intact. The `email` OIDC
scope may remain to receive an address when present; requesting it does not make
an address mandatory.

After that, explicitly change the known legacy `email` values `lucky`, `sonia`,
and `vitoria` to NULL. Do not apply a blanket heuristic to the user database.
Back up before the schema/data migration; an older release with NOT NULL email
is not a safe rollback after NULL values have been introduced.

## 2. Local logout followed by provider logout

Reference behavior: `pkgs/jellyfin-web/logout.patch` clears local authentication
and cache state, then navigates to Authentik's provider end-session page. Keep
Authentik's logout choices visible; do not silently force a global SSO logout.

### Configuration and session provenance

- Proposed per-provider setting: `logoutMode: "local" | "provider"`, defaulting
  to `"local"` for backward compatibility. Foundry opts into `"provider"`.
  Add it to the settings type, declarative schema/strict key allowlist, and
  configuration documentation. Do not add an arbitrary browser-supplied URL.
- On successful OIDC **login**, record the authenticating provider slug in the
  server-side session, alongside `userId`. Do not retain ID/access/refresh
  tokens solely for logout.
- Account linking must not change the session's login provider. Successful
  local/Plex/Jellyfin/Quick Connect logins must clear any old OIDC provenance.
- Resolve logout from the provider that authenticated this session, not the
  first configured provider or an arbitrary linked account. Existing sessions
  without provenance perform local logout only; no guessing.

### Server flow

Extend `POST /api/v1/auth/logout` while preserving its existing cleanup:

1. Capture the session's provider slug, then destroy the local session and clear
   its cookie using the same cookie name/path/domain settings used at creation.
   An already-expired session still gets cookie cleanup and a successful local
   logout response.
2. Only after successful local destruction, if that provider is configured for
   provider logout, obtain `end_session_endpoint` from its OIDC discovery
   metadata. Bound discovery with a short timeout; use safe cached metadata if
   the client already has a suitable cache.
3. Validate the discovered endpoint as an absolute HTTPS URL (honor the existing
   explicit insecure-development policy only in development). Do not fetch a
   URL supplied by the browser. A removed provider, missing endpoint, discovery
   outage, or invalid URL falls back to local logout with a sanitized warning.
4. Return `{ status: "ok", redirectUrl?: string }`. Preserve compatibility for
   clients that only inspect `status`.

For Foundry's Authentik behavior, navigate to the bare discovered end-session
endpoint: no `id_token_hint`, `post_logout_redirect_uri`, automatic global
logout flag, or untrusted return URL. This intentionally matches the Jellyfin
patch, rather than implementing the full RP-initiated logout protocol. Other
providers may require more parameters; do not claim generic interoperability
without testing them. A provider failure must never resurrect a Seerr session.

Local session destruction failure must remain an error, with no success response
or provider redirect. Do not mask a still-live Seerr session behind SSO logout.

### Browser flow

In `src/components/Layout/UserDropdown/index.tsx`:

- Retain bounded push-unsubscription cleanup and local push-preference removal.
- After successful local logout, clear client authentication/user cache state.
  Avoid a revalidation-triggered login navigation racing the provider redirect.
- Use `window.location.assign(response.data.redirectUrl ?? "/login")` for a
  hard navigation. Do not navigate to the IdP before the logout request succeeds.
- A failed local logout remains visible and does not navigate to Authentik.
- Update the logout response contract in `seerr-api.yml` and relevant types.

### Acceptance tests

1. A provider-authenticated session returns its discovered end-session URL only
   after session destruction; subsequent authenticated API requests reject.
2. Browser cleanup precedes hard navigation; Authentik's provider logout choices
   remain visible. Test both leaving the wider SSO session intact and explicitly
   ending it through Authentik's own UI.
3. Local logins, pre-upgrade sessions, and expired sessions still log out locally.
4. Multiple configured/linked providers choose the session's authenticating one;
   linking another provider does not alter that choice.
5. Missing/removed providers, missing metadata, discovery timeout/outage, and
   invalid endpoint schemes all leave Seerr logged out and return no redirect.
6. Session-store destruction failure returns an error and no provider redirect.
7. No identity tokens, client secrets, or correlation cookies leak into logs or
   redirect URLs. No new open-redirect input is accepted from the browser.

### Foundry rollout

Set `logoutMode: "provider"` on the Authentik provider after the patched build
lands. Existing sessions acquire provenance on their next login; do not rewrite
sessions to infer it from linked accounts. Verify an actual browser logout and
an authenticated API request afterward. Provider logout is not a promise of
continuous authorization or instantaneous revocation of other Seerr sessions.

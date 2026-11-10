# Firefly authentication

Browser access uses Authentik; `trusted` and `admin` receive the `firefly/access`
entitlement. Firefly creates a separate financial administration on first login.
The tailnet restriction remains in place, including for API clients.

## Before switching the existing installation

1. Back up Firefly's database and state.
2. In Authentik, set Gabs's **user attribute** `firefly_principal` to
   `gabriel@gsfontes.com`, the existing Firefly account identifier. Preserve all
   other attributes. Do this **before the first SSO login**, otherwise Firefly
   will create a new, empty account. This is an administrator-managed attribute;
   never expose it in user-editable profile fields.
3. Disable Firefly's own MFA if enabled; Authentik handles browser authentication.
4. Apply the configuration and confirm the `Foundry - Firefly` and
   `Foundry - outposts` blueprints succeeded. The embedded outpost must contain
   **both** Radicale and Firefly.
5. Check that SSO opens the existing financial administration and that creating
   and revoking a personal access token works.

New users default to their Authentik UUID as their Firefly identifier. Firefly
stores this identifier in its `email` column; the separate `REMOTE_EMAIL` value
supplies the contact email. Do not change a principal once it owns financial data.
Remote-user provisioning does not require enabling public registration.

Browser authentication also syncs the Authentik username into the
`remote_guard_display_name` preference through a URL-encoded `REMOTE_DISPLAY_NAME`
CGI variable. Both UI account labels use it, falling back to the contact email and
then the stable identifier. This never changes the account lookup or PAT ownership;
API requests do not update the preference.

## API clients

Use a distinct Firefly personal access token for each Waterfly installation and
for the PTAX job. `/api/` bypasses Authentik redirects, not Firefly authentication:
Passport validates bearer tokens and its own CSRF-protected browser API cookies.
Client-supplied identity headers cannot set the CGI identity variables.

The existing PTAX token remains valid because the account is not migrated. Rates
are scoped to its financial administration; this job does **not** update every
user, and its 3.5% card markup should not be silently applied to other users.
Revoking Authentik access does not revoke Firefly PATs; revoke those separately.

## Acceptance checks

- Anonymous browser navigation redirects to Authentik; users without access are denied.
- A second allowed user gets an empty administration, not Gabs's transactions.
- Missing/invalid API tokens fail without redirecting to Authentik, even with forged
  `Remote-User` or `X-Foundry-Firefly-Principal` headers.
- Waterfly and the existing PTAX job still work with their existing tokens.
- Browser charts/autocomplete still work (they use Firefly's own API cookie).
- `/relatorio-layla` no longer serves the static report, and Radicale login still works.

To roll back, revert the configuration change; existing accounts and tokens are
not rewritten. Accounts created by SSO have random local passwords.

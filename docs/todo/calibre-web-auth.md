# Calibre-Web authentication

Prepared, not yet verified live. Browser and OPDS logins use Authentik-issued
app passwords through LDAP, not independent Calibre-Web passwords. This is
centralized password authentication, not browser SSO or a WebAuthn ceremony.
The separate `calibre.m7.rs` content server and Readarr's local writes remain
unchanged.

## Bootstrap

1. Deploy the Alcyone Blueprint change first. It creates `book-users`, the
   Calibre-Web LDAP provider/application, `calibre-web-search` service account,
   and the manually deployed `Merope LDAP` outpost definition.
2. In Authentik's Outposts page, open deployment information for `Merope LDAP`.
   Privately copy its generated token into Merope's SOPS file as
   `authentik-ldap-outpost-token`. Do not generate an unrelated API token or
   paste it in chat. Then deploy the Merope outpost/package change.
3. Confirm `authentik-ldap.service` is healthy. It listens on loopback only:
   LDAP `127.0.0.1:3389`, LDAPS `127.0.0.1:6636`, metrics `127.0.0.1:9302`.
   Calibre-Web uses local LDAP; the outpost contacts Authentik over verified
   HTTPS. No public or tailnet LDAP port is opened.
4. Add intended people to `book-users`. Match each existing Calibre-Web
   **username**, not just their email, to their Authentik username before
   switching login types. Preserve existing Calibre-Web users and permissions;
   do not delete the application database or book library.
5. Create an Authentik **app password** for the `calibre-web-search` service
   account. It is a service-to-service credential, stored in Calibre-Web's
   encrypted settings through the admin UI. The service account has directory
   search permission only on this LDAP provider and is not an IdP administrator
   or a member of the book import group.

## Calibre-Web settings

In Admin → Edit Basic Configuration → Feature Configuration:

| Setting | Value |
|---------|-------|
| Login type | LDAP authentication |
| LDAP server | `127.0.0.1` |
| LDAP port | `3389` |
| LDAP encryption | None (loopback only) |
| LDAP authentication | Simple |
| Administrator username | `cn=calibre-web-search,ou=users,ou=calibre-web,dc=ldap,dc=m7,dc=rs` |
| Administrator password | The service account's Authentik app password |
| Distinguished name | `ou=calibre-web,dc=ldap,dc=m7,dc=rs` |
| User object filter | `(&(objectclass=user)(cn=%s))` |
| Group object filter | `(&(objectclass=group)(cn=%s))` |
| Group name | `book-users` |
| Group members field | `member` |

Disable anonymous browsing, public registration, remote/magic-link login and
Kobo tokens. Do not enable trusted-header authentication. Import LDAP users
from Admin, then assign their Calibre-Web permissions; group membership does
not grant application administration. Users create/revoke their own app
passwords in Authentik and enter their username and app password in the browser
or OPDS client (`https://books.m7.rs/opds`). Ordinary Authentik account passwords
and API tokens are deliberately not accepted by this LDAP bind flow.

## Remove independent passwords

After confirming LDAP login for the existing administrator and importing users,
stop Calibre-Web and back up `app.db` privately, outside the repository/store.
Clear **all** local password hashes, including those of imported users:

```sql
UPDATE user SET password = '';
```

Run this against `/var/lib/calibre-web/app.db` while the service is stopped,
then restart. An empty stored hash cannot authenticate, including with an
empty submitted password. This preserves users, shelves and permissions.

No downstream authentication patch is retained. Upstream can fall back to local
passwords when LDAP fails, so do not set/reset local passwords afterward; clear
hashes again after future imports. LDAP mode hides the local password-reset
button, but this is not a claim that every local-password-writing code path
has been removed. Existing application sessions are separate from LDAP binds.

## Checks and recovery

- Test browser and OPDS login with an Authentik app password.
- Verify an unbound user and an ordinary account password are rejected.
- Revoke a disposable app password in Authentik; verify a fresh LDAP/OPDS login
  fails. Direct bind/search avoids credential-result caches; already logged-in
  browser sessions are not reauthenticated on every request.
- Stop the outpost briefly and confirm the old Calibre-Web password cannot
  authenticate. Restart it afterward.
- `auth.m7.rs` is configured for public HTTPS, so app-password self-service no
  longer requires tailnet enrollment once that change is deployed. App passwords
  are not per-provider scoped by default; do not describe them as Calibre-only
  tokens.

Recovery is independent SSH and administrative database access. Restoring an
old application database can restore old local password hashes too; clear them
again before reopening access. Do not delete accounts to reset authentication.

# Shared application groups

Authentik's `users` and `admins` groups grant access to Jellyfin, Immich, and
Grafana. `admins` grants ordinary access too; membership in both is unnecessary.
Neither group grants Authentik superuser privileges. Application roles are OIDC
claims, not Authentik RBAC roles or additional membership groups.

| Group | Jellyfin roles | Immich role | Grafana organization role |
| --- | --- | --- | --- |
| `users` | `jellyfin-users` | `user` | `Viewer` |
| `admins` | `jellyfin-users`, `jellyfin-admins` | `admin` | `Admin` |

Jellyfin manages permissions from these roles: everyone gets all libraries,
audio transcoding is allowed, video transcoding is disabled, and only admins
receive administrator status. The plugin's other playback/management fields
use their role-mapping defaults; existing per-user library restrictions are
replaced. Grafana organization Admin does not grant Grafana server-admin access.
Immich quota claims and existing quotas are unchanged.

## Migration

Before deploying or pushing to the auto-deployment branch:

1. Create `users` and `admins` in Authentik if they do not exist. Leave their
   superuser flags off.
2. Assign intended users manually. Anyone in either group will gain access to
   all three applications; anyone in neither will be denied new OAuth access.
   Put the intended application administrators in `admins` before their next
   login, or their application admin status can be removed.
3. Deploy the Alcyone provider/group changes before the Merope client changes.
   The new custom scopes must exist before clients request them. Until Merope
   switches, Jellyfin's old local group gate still requires `jellyfin-access`.
   Keep that old membership through the transition if access is needed.
4. Sign in again to each app and verify the expected role. Jellyfin and Immich
   apply role changes on login, not immediately when group membership changes.
   Revoke existing sessions as needed when removing access or admin privileges.
5. Once all clients are switched, remove unused legacy app-specific groups in
   Authentik. The blueprints stop managing them but do not delete them.

Access bindings are identified by application and order, not group. This updates
existing bindings in place, replacing the old app-group grants rather than
leaving an alternative access path. Manually added bindings outside the declared
orders need a separate audit.

The provider mappings use `jellyfin_roles`, `immich_roles`, and `grafana_roles`
scopes. Each mapping emits only its application's roles. Users removed from
`admins` but retained in `users` receive explicit non-admin roles on their next
login, so the old administrator role is not retained through a missing claim.

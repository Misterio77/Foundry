# Alcyone service split

Goal: keep alcyone focused on infrastructure and trust; move applications to
taygeta without changing existing domains or shared-service UX.

## Placement

Keep on **alcyone**: Headscale/DERP, Authentik, mail core (Postfix, Dovecot,
Rspamd, DKIM, mail storage and autoconfiguration), Git repositories with SSH/HTTPS
access, and their required databases, nginx routes, exporters and backups.
SMTP delivery stays public; submission and IMAP stay tailnet-only.

Move to **taygeta**:

| Service | Access |
| --- | --- |
| Firefly III | Public HTTPS; preserve Layla's login flow |
| Radicale, calendar/contact sharing and browser UI | Public HTTPS; preserve URLs, credentials, principals and sharing |
| FreshRSS, Grafana | Public HTTPS with authentication |
| File server | Public HTTPS; replace network restrictions with explicit authentication |
| Prometheus | Preserve tailnet/loopback restriction and `/metrics` client-certificate requirement |
| Website, short links, redirects, Robohash/avatars | Public HTTPS |

## Removal

- [x] Remove SOGo6 API/UI, dedicated Redis, nginx application routes, Authentik
  blueprint/secret injection and package/module/patch code from configuration.
  Preserve mail/DAV services, shared identity mappings/scopes and `gablogin-cli`.
- [ ] Retire live SOGo Authentik objects and revoke its grants at deployment;
  removing the blueprint does not delete existing objects.
- [x] Remove SOGo persistence, database/user and backup declarations; no ongoing
  retention is required. Live state deletion and encrypted-secret cleanup remain
  separate decisions.
- [ ] Confirm whether `git://` is used; remove git-daemon and public TCP 9418 if not.

## Migration order

- [ ] Retire SOGo6 after confirming neither user needs its combined web UI; check
  native mail/calendar clients and Radicale's browser interface.
- [ ] Move static sites, redirects and avatars.
- [ ] Move files and FreshRSS, establishing authentication before public access.
- [ ] Move Firefly and Radicale separately: consistent backups, final transfer
  with writes stopped, rollback plan and shared-client/UX validation.
- [ ] Move Grafana and Prometheus, updating scrape destinations and credentials.
- [ ] Prune obsolete alcyone routes, credentials, database roles/databases and
  dependencies after validation; retain backups for an agreed period.

For every move, transfer state, databases, credentials, persistence, backups and
monitoring. Route application ingress directly to taygeta, not through alcyone.
Replace localhost Authentik assumptions with a supported remote outpost or
restricted cross-host arrangement; narrowly scope tailnet access.

Taygeta still shares a kernel with game-server and trusted build workloads. A
separate application VM is a possible follow-up, not part of this migration.

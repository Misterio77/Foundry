# Alcyone service split and upgrade hardening

## Goal and accepted trust

Reduce Alcyone's executable attack surface and resource contention while keeping
sensitive, uptime-critical infrastructure there. Static nginx hosting is not a
priority for removal; public dynamic applications with tolerable downtime are.
Alcyone is the only VPS with reliable outbound SMTP.

Builders and the binary cache remain trusted for artifact contents. A compromised
Taygeta or Celaeno can prepare poisoned outputs ahead of a legitimate deployment.
Source authorization checks do not prove faithful builds or bind the CI-provided
output path to the authorized source. This residual risk is accepted alongside
regular updates, monitoring, auditing and operator review.

No local NixOS evaluation on Alcyone, x86 emulation on Celaeno, or workstation
remote-builder access is planned. Keep periodic unattended upgrades; do not add a
manual release-approval requirement.

## Placement

| Host | Responsibilities |
| --- | --- |
| Alcyone | Mail/autoconfiguration, Authentik, Headscale/DERP, authoritative Git, static websites/shortlinks/redirects, files, Prometheus; future logging/audit storage |
| Taygeta | Firefly, Radicale, FreshRSS, Grafana, avatars, screenshare, native x86 builds |
| Celaeno | Nixbot, binary cache, native ARM builds |
| Merope | Media, photos, residential downloads, bulk storage and backup repositories |

Taygeta has 16 GB RAM / 4 vCPUs; Celaeno has 12 GB / 2 ARM vCPUs. Retiring
Taygeta's seldom-used games frees capacity, but parallel builds can still contend
with applications. Merope's 8 GB Raspberry Pi has substantial storage but limited
CPU/GPU capacity; keep residential and bulk-data workloads there.

Preserve existing domains and access policies. FreshRSS and files remain
tailnet-only. Grafana remains public with Authentik authentication. Application
ingress goes directly to Taygeta, not through Alcyone as a reverse proxy.

## 1. Harden auto-upgrades

Implementation targets:

- `modules/nixos/nixbot-auto-upgrade.nix`
- `hosts/nixos/common/global/auto-upgrade.nix`
- `hosts/nixos/celaeno/services/nixbot.nix`

### Authenticated source and independent authorization

- [ ] Confirm the exported HTTPS Git URL on Alcyone; the existing dumb-HTTP route
  expects a `.git` repository name.
- [ ] Use HTTPS with certificate verification for host-side source retrieval and
  Nixbot repository polling. Do not introduce new SSH credentials.
- [ ] Fetch the configured branch into a root-owned verification repository and
  record its fetched tip as the authoritative snapshot for the upgrade attempt.
- [ ] Validate the CI candidate revision and output-path fields.
- [ ] Require the candidate revision to be an ancestor of, or equal to, that
  fetched branch tip. Do not trust CI's branch label as proof of membership.
- [ ] Verify the candidate commit's SSH signature against an allowed-signers file
  installed by the host configuration, derived from the trusted public key.
  Never obtain the trust root from CI or the candidate tree.
- [ ] Only after authorization succeeds, apply the existing freshness policy,
  retrieve the output and activate it.
- [ ] Fail closed on transport errors, missing history, malformed responses,
  signature failures or branch mismatch; leave the running system/profile alone.
- [ ] Log the candidate revision, fetched branch tip, verification outcome and
  selected output path.

An ancestor is acceptable so the latest successful build can deploy while a newer
branch tip is still building. Commit timestamps remain a freshness heuristic, not
cryptographic anti-rollback protection. Retain the native Git daemon unless a
separate consumer audit justifies retiring it.

### Verification cases

Use temporary repositories for ad-hoc checks; do not introduce a standalone test
harness without an existing suite to run it.

- [ ] Accept a correctly signed candidate on the intended branch.
- [ ] Reject a signed candidate reachable only from another branch.
- [ ] Reject unsigned candidates and signatures from unauthorized keys.
- [ ] Reject fabricated or missing revisions.
- [ ] Accept an authorized ancestor behind the fetched tip when it passes the
  installed system's freshness check.
- [ ] Confirm fetch/authorization failures cannot change profiles or activate an
  output.

## 2. Prepare Taygeta

- [ ] Remove Minecraft/Dynmap and Factorio from the active configuration; save
  archival/deletion is a separate operator decision.
- [ ] Declare backups, persistence and monitoring for incoming application state.
- [ ] Review build concurrency and resource budgets for the four-vCPU host.
- [ ] Scope each application's credentials to its needs and encrypt them for
  Taygeta without granting access to Alcyone's entire host-specific secret file.
- [ ] Move application databases with applications. Keep only databases required
  by retained services on Alcyone.

## 3. Move applications independently

| Order | Application | Required behavior |
| --- | --- | --- |
| 1 | Grafana | Preserve public OAuth login and state; provide narrowly scoped Prometheus query access from Taygeta |
| 2 | Firefly | Preserve database, application state, scheduled jobs, both users' login flows, API access and mail |
| 3 | FreshRSS | Preserve database/state, API credentials and feed jobs; retain tailnet-only ingress |
| 4 | Avatars | Move generator/cache, remove Alcyone's localhost hostname override, preserve Authentik fetching and graceful failure |
| 5 | Radicale | Preserve URLs, stable principals, collections, sharing, client credentials, directory integration and browser/client synchronization |

- [ ] Move Grafana.
- [ ] Move Firefly.
- [ ] Move FreshRSS.
- [ ] Move avatars.
- [ ] Move Radicale.

Replace localhost Authentik assumptions with a narrowly scoped remote outpost or
restricted cross-host access to the existing outpost endpoints. Choose the
integration during implementation; do not broadly expose localhost-only APIs.
Review Radicale's directory token and each application's mail/identity authority.

Each move must include consistent backup coverage, persistence, credentials,
monitoring and explicit client-workflow acceptance checks. Require a single
writable authority and a rollback strategy that accounts for destination writes.
Keep live transfer commands, DNS cutover procedures and retention/deletion
instructions outside this repository.

## 4. Keep observability storage on Alcyone

Prometheus provides an independent record, not proof that a compromised target is
telling the truth. Scrape client certificates authenticate the collector to the
exporter; a compromised exporter still controls its responses. Future remote logs
can preserve received history but cannot force a compromised sender to report
honestly.

- [ ] Preserve exporter client-certificate checks and update moved scrape targets.
- [ ] Restrict Grafana to the required query interface; do not expose Prometheus
  administrative endpoints. Keep remote-write ingestion disabled unless needed.
- [ ] Bound scrape timeouts, response sizes, samples and labels for less-trusted
  targets.
- [ ] Budget Prometheus CPU, memory and storage so it cannot starve mail/identity.
- [ ] Alert on failed upgrades, missing targets and storage pressure.

Future logging/auditing is separate work: per-host ingestion identities, bounded
resource usage and no sender permission to delete or rewrite retained history.
Tailnet membership alone is not sufficient authorization between these hosts.

## 5. Remove residual dependencies and authority

- [ ] Remove obsolete Alcyone application routes, secrets, database roles,
  persistence and backup declarations after each move is accepted.
- [ ] Remove PHP and other runtimes when no retained service requires them.
- [ ] Narrow cross-host access to required mail, identity, monitoring, backup and
  deployment flows; avoid broad shared-secret access.
- [ ] Ensure backup retention/deletion authority is outside the application host.
- [ ] Verify retained services remain usable when Taygeta is unavailable.

Acceptance criterion: losing Taygeta costs applications, not mail, identity, VPN
coordination, Git, or access to monitoring history. Check indirect dependencies,
including Authentik avatar fetching and monitoring scrape/query behavior.

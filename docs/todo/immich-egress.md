# Immich egress containment

Proposal only: no outbound filtering is implemented by this document.

## Goal and remaining trust

Stop an Immich compromise from opening connections to unrelated host services,
LAN devices, or tailnet peers. Preserve native mobile uploads, OIDC, sharing,
background processing and model downloads. Filesystem isolation does not filter
TCP connections, including loopback.

An RCE in the server still compromises all Immich media and its database. It can
also send data back over legitimate incoming HTTP connections. Egress filtering
contains lateral movement; it is not a guarantee against photo exfiltration.

## Recommended first implementation

Use an nftables output chain matching dedicated service UIDs. Keep the host's
existing input policy; do not globally restrict Merope's outbound connections.
Prefer rejecting disallowed new connections so mistakes fail promptly.

Before enforcing:

- Give machine learning a separate system user/group. It currently shares the
  server's `immich` identity. Let systemd migrate ownership of its cache, and
  verify model loading. It does not need the media tree, PostgreSQL or Redis.
- Resolve usernames to UIDs at rule installation; never hard-code allocated UIDs.
  Ensure filtering is installed before starting both services, including
  during boot and ruleset reloads. Fail closed if identity lookup fails.
- Cover both IPv4 and IPv6 using an `inet` table. Inspect how NixOS installs and
  reloads its current firewall before choosing the rule integration point.

### Connection matrix

| Source | Permit new connections to | Purpose |
| --- | --- | --- |
| nginx | Immich backend on loopback, TCP 2283 | Web, mobile and native shared-link ingress |
| Immich server | ML listener on loopback, TCP 3003 | Face recognition, search, OCR |
| Immich server | Authentik's selected addresses, TCP 443 | Discovery, JWKS, token exchange, userinfo |
| Immich server | Selected DNS resolver, UDP/TCP 53, if needed | Name resolution |
| ML | Approved HTTPS download destinations or a controlled egress proxy | Model downloads |
| Both services | Replies to permitted incoming/established connections | Responses, including uploads and websockets |

PostgreSQL and Redis use filesystem Unix sockets, not TCP; preserve the server's
existing access. Do not allow arbitrary loopback traffic just to accommodate them.
DNS may use the host's nscd Unix socket; verify the actual resolver path before
adding an unnecessary network exception.

For both identities, deny everything not expressly allowed. In particular,
there must be no blanket loopback, LAN, tailnet, IPv6 link-local or public HTTPS
exception. Blocking private IPv4 ranges alone would leave public-addressed
internal services and IPv6 reachable. Established-flow handling must not leave
pre-policy outbound connections alive after rollout: stop the services before
initial enforcement and restart them after the policy is active.

### OIDC and HTTPS caveats

Verify the deployed resolution of `auth.m7.rs` from Merope before selecting allowed
addresses. Headscale generates private DNS records from tailnet IP allowlists;
Authentik's metrics now use client-certificate authentication instead and do not
cause a private DNS override. Do not assume a tailnet address, including during
migration from older DNS records. Keep IPv4 and IPv6 destination sets current with
atomic updates; retain TLS certificate validation and the public issuer URL.

An IP/port exception for Alcyone:443 also permits reaching its other nginx
virtual hosts, including tailnet-only ones. UID filtering cannot distinguish
HTTPS Host/SNI, so this is a residual lateral-movement path, not full IdP-only
isolation. The stronger follow-up is a separate IdP-only listener/address or a
controlled gateway with a fixed upstream and no general CONNECT facility.

Do not assume Node, Python, ONNX or download libraries honor proxy environment
variables. Test each actual client before relying on an explicit HTTP proxy.
Inventory model-download redirects/CDNs without logging signed URLs or tokens;
pre-seeding models and disabling runtime downloads is an alternative to a large
allowlist. Check optional server-side outbound features (profile pictures,
reverse geocoding, update checks, webhooks, external storage integrations) and
explicitly enable or disable their dependencies. Browser-fetched map tiles are
not automatically a server egress requirement.

## Rollout and acceptance

1. Deploy distinct identities and filesystem isolation first. Verify OAuth,
   uploads, sharing, processing and database backups.
2. Inventory actual destination metadata, not HTTP bodies, credentials or photo
   contents. Draft exact rules and validate their syntax before activation.
3. Keep an independent admin SSH session and a timed rollback for the firewall
   change. Stop the affected services, activate policy, then restart them.
4. Test both IPv4 and IPv6 from each service's real UID and sandbox/cgroup:
   - Browser and mobile login, token exchange, logout, uploads and websocket replies.
   - Public shared-link rendering and downloads.
   - A cold model download, OCR, face recognition and search.
   - Immich's scheduled database backup.
   - Rejected connections to local *arr APIs, local nginx, Alcyone's node exporter,
     another LAN host, and an arbitrary public destination. Use read-only probes.
5. Repeat the boundary tests after reboot and firewall reload; check counters.
   Do not describe the policy as enforced until those live tests pass.

## Stronger boundary if needed

A dedicated network namespace with explicit ingress and egress gateways avoids
UID matching as the primary boundary and can also constrain Unix-socket exposure.
It requires rewiring nginx upstreams, ML connectivity, DNS and OIDC networking;
plan that as a separate change rather than silently breaking localhost listeners.
Neither namespaces nor UID rules should expose the host's Nix daemon, container
sockets or other execution brokers that could originate traffic on the attacker's
behalf. Tailnet ACLs remain worthwhile defense in depth, but cannot govern local
loopback or LAN traffic.

# Operations and proposals

- [Authentik / Gablogin](authentik.md): intended user experience, per-service assessment and known exceptions.
- [Mail, DAV and SOGo](mail-auth.md): integrated login, oama-managed OAuth and the app-password fallback; validation and client acceptance.
- [Metrics client certificates](metrics-mtls.md): mTLS access, provisioning and rotation.
- [Backups](backups.md): declared coverage, restore evidence and gaps.
- [Gablogin user-facing contract](todo/gablogin-api-auth.md): two preferred paths—integrated login and helper-managed OAuth—with a shared app-password fallback; trade-offs and lifecycle decisions.
- [Immich egress](todo/immich-egress.md): proposed lateral-movement containment.
- [Atelier publishing](todo/atelier-publishing.md): unimplemented artifact boundary.

Keep operational constraints and unresolved decisions here. Implementation details
belong in code; completed-work narratives belong in version history. Configured
behavior is not proof of deployment or a successful live test.

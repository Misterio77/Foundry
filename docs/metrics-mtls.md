# Metrics client certificates

HTTPS scrape jobs present a dedicated Prometheus client certificate. nginx requests
client certificates optionally across all TLS vhosts via shared HTTP settings,
then requires successful verification on metrics locations only. Normal application
authentication, tailnet ACLs, and Let's Encrypt server certificates are unchanged.
Plain HTTP host-exporter jobs still use the tailnet. Asterope's HTTP-only default vhost retains its existing
IP ACL rather than pretending client certificates work over HTTP.

Metrics locations check `$ssl_client_verify` and return 403 unless it is `SUCCESS`.
Vhosts with a server-level IP ACL retain it: their metrics require both tailnet
access and a valid client certificate. These private vhosts keep their tailnet DNS
overrides; public vhosts such as Headscale use public DNS and certificate-only
metrics authentication. Every certificate issued by the dedicated metrics-client
CA satisfies the certificate check; do not reuse a general-purpose client CA.

Clients without a certificate can still use application paths under their existing
access policies. A client presenting an invalid or expired certificate can be
rejected even on non-metrics paths, since verification happens before location
handling.

## Issue and import before deployment

Initial credentials were issued and imported on 2026-11-07. The Prometheus client
certificate expires on 2027-11-07; the CA is valid for ten years. The CA private key
and public certificate are stored together in the encrypted password-store entry
`m7.rs/metrics-client-ca`; neither is printed during provisioning. Only the public
CA certificate is distributed to nginx hosts.

For a replacement CA, run the following in a private directory outside the
repository (with OpenSSL available, e.g. `nix-shell -p openssl`). Keep the CA private
key in secure storage; nginx only receives its public certificate.

```sh
umask 077
openssl genpkey -algorithm ED25519 -out metrics-ca.key
openssl req -new -x509 -key metrics-ca.key -out metrics-ca.pem \
  -days 3650 -subj '/CN=Foundry metrics client CA' \
  -addext 'basicConstraints=critical,CA:TRUE,pathlen:0' \
  -addext 'keyUsage=critical,keyCertSign,cRLSign'

openssl genpkey -algorithm ED25519 -out prometheus.key
openssl req -new -key prometheus.key -out prometheus.csr \
  -subj '/CN=prometheus'
printf '%s\n' \
  'basicConstraints=critical,CA:FALSE' \
  'keyUsage=critical,digitalSignature' \
  'extendedKeyUsage=clientAuth' > client.ext
openssl x509 -req -in prometheus.csr -CA metrics-ca.pem -CAkey metrics-ca.key \
  -CAcreateserial -out prometheus.pem -days 365 -extfile client.ext
openssl verify -purpose sslclient -CAfile metrics-ca.pem prometheus.pem
```

From the repository, edit the encrypted files yourself with sops. Add these YAML
keys as literal block scalars (`key: |` followed by the indented PEM contents):

- `sops hosts/nixos/common/secrets.yaml`: `metrics-client-ca`, containing
  `metrics-ca.pem`. This certificate is public, but using the existing shared sops
  file distributes it consistently to nginx hosts without a placeholder CA.
- `sops hosts/nixos/alcyone/secrets.yaml`: `prometheus-client-cert`, containing
  `prometheus.pem`, and `prometheus-client-key`, containing `prometheus.key`.

Never import `metrics-ca.key` into a deployed host's secrets. Do not deploy until
all three keys exist: sops-nix cannot activate the configuration without them.
The client files are owned by `prometheus` with mode `0400`; the CA is read by the
nginx master. Secret changes restart the respective services.

## Rollout and verification

Deploy the scraper first so it presents the certificate while old source-IP ACLs
still work, then deploy nginx hosts. If deploying alcyone's combined roles together,
expect a brief scrape interruption until both services have restarted.

From a machine outside the tailnet, test a public endpoint:

```sh
curl -i https://tailscale.m7.rs/metrics                        # 403
curl --cert prometheus.pem --key prometheus.key \
  https://tailscale.m7.rs/metrics                             # 200, metrics
curl -i https://tailscale.m7.rs/key                           # 200, no client cert
```

A client certificate from an unrelated CA must not get metrics (nginx may return
400 during client verification rather than the location's 403). Also test the
private vhosts from outside their IP allowlist: metrics and application paths must
remain forbidden even with a valid certificate. From the tailnet, metrics require
a valid certificate while application paths retain their existing policies. Check
Prometheus targets for all HTTPS jobs; scrape addresses and instance labels have
not changed.

## Rotation

Recover the CA key and certificate with `pass show m7.rs/metrics-client-ca` into a
mode-0600 file in a private directory, never into terminal output or the repository.
The entry contains the private-key PEM followed by the public CA-certificate PEM.

Issue a new client certificate before its one-year expiry and replace the two
Prometheus sops entries. nginx does not need a change when the CA stays the same.
Track expiry explicitly; sops-nix distributes credentials but does not renew them.

For CA rotation, temporarily put both CA certificates in `metrics-client-ca`,
deploy all nginx hosts, replace the scraper certificate/key with one issued by
the new CA, then remove the old CA and redeploy nginx. To revoke a compromised
client without a CRL mechanism, replace the CA and client credentials; deleting
an old client secret alone does not revoke copies of that certificate.

# Server network access, HTTPS and reverse proxies

AuthLens Server supports a specifically configured private LAN endpoint over HTTPS. Desktop remains loopback-only. Use dedicated installation,
data, keys and certificates; deployment does not infer credentials, TLS or existing data. Current verification boundaries are in
[acceptance status](../validation/STATUS.md).

## 1. Hosting boundary

- Default: loopback only. Desktop always uses `127.0.0.1` and an OS-assigned port.
- Network Server requires `--network`, one specific private `--listen` address, a fixed port, a usable certificate and explicit `--allowed-hosts`.
- All-interface, public, multicast and loopback addresses are refused for network mode. Hostnames are exact; wildcards are refused.
- Direct allowed hosts must be covered by the backend certificate SAN. A certificate also needs a private key, validity, server-authentication usage
  and adequate key strength. Clients and proxies must independently validate chain trust and the name they connect to.
- A TLS startup self-check verifies that the operating system can use the private key. Windows ephemeral keys are prepared for SChannel.
  Do not disable TLS verification to work around a handshake failure.

## 2. Configuration

CLI options override their `AUTHLENS_*` environment counterparts. Unknown or incomplete options fail closed. Use `AuthLens.Api --help` for the
complete maintenance-command reference. Secrets are not accepted on the command line.

| Option | Environment | Purpose |
| --- | --- | --- |
| `--data-dir` | `AUTHLENS_DATA_DIR` | Absolute dedicated local data directory |
| `--listen` | `AUTHLENS_LISTEN` | Specific listen IP |
| `--port` | `AUTHLENS_PORT` | Fixed network port |
| `--network` | `AUTHLENS_NETWORK=true` | Explicit LAN enablement |
| `--allowed-hosts` | `AUTHLENS_ALLOWED_HOSTS` | Direct HTTP hosts with backend SAN coverage |
| `--proxy-hosts` | `AUTHLENS_PROXY_HOSTS` | Public HTTP hosts accepted only from trusted TCP peers |
| `--trusted-proxies` | `AUTHLENS_TRUSTED_PROXIES` | Verified proxy IPs or narrow CIDRs; default none |
| `--trusted-proxy-hops` | `AUTHLENS_TRUSTED_PROXY_HOPS` | Maximum trusted hops, default 1, range 1–5 |
| `--cert` | `AUTHLENS_CERT` | PFX/PKCS#12 or PEM certificate |
| `--cert-key` | `AUTHLENS_CERT_KEY` | PEM private-key path |
| `--cert-password-file` | `AUTHLENS_CERT_PASSWORD_FILE` | Protected password file |
| `--auth` | `AUTHLENS_AUTH` | `accounts` by default; `shared-token` for isolated clients/tests |
| `--no-worker` | — | Disable the import worker for isolated diagnostics |

`AUTHLENS_CERT_PASSWORD` is an environment-only alternative when no password file is configured. The generated/protected API capability and
`AUTHLENS_PRINCIPAL` belong to local automation; they do not replace an administrator account for account/storage administration.

## 3. Local accounts and sessions

Server stores local accounts in `<data-dir>/security/accounts.sqlite3`, separately from business evidence. Passwords use Argon2id verification;
account activation/recovery codes are local, one-use and expire. Bootstrap through the supported local administration workflow or
`AuthLens.Api --data-dir <directory> --accounts-code`. Never log or commit the returned code or credentials.

Sessions use host-only Secure, HttpOnly, SameSite=Strict cookies over HTTPS. Each account session has its own CSRF secret. The frontend echoes
that value on writes in addition to same-origin enforcement. Session identifiers, CSRF values and one-time codes are stored as digests where applicable.
Failed sign-ins are throttled. Unknown users receive the same password-verification path.

Permissions are enforced per route: viewers read/export, reviewers also record permitted decisions, administrators manage data/settings/accounts.
Unknown writes are denied. Account management requires a real administrator session. Permanent deletion checks expected revision and exact username,
prevents self-deletion and deletion of the last active administrator, removes credentials/sessions/one-time codes and minimizes attributable security
metadata while preserving opaque audit links and immutable business evidence. Retained backups remain protected and can contain earlier account state.

## 4. Host, Origin and CSRF

State-changing browser requests need the exact effective scheme/host/port to match Origin, or the supported same-origin browser signal when Origin
is absent. Invalid, opaque, foreign or wrong-port origins are rejected. Session CSRF verification and authorization still apply afterwards.
Do not configure permissive CORS, wildcard origins or trust-all proxies. HTTPS cannot be downgraded by forwarded headers; secure cookies and
HSTS remain enabled. Static assets and health endpoints contain no authenticated business data.

Boundary refusals include a correlation ID. Protected server logs contain sanitized raw/effective host/scheme, Origin comparison, original TCP peer,
trust/application status and parsed forwarded values. They do not echo cookies, authorization, credentials or arbitrary malformed header content.

## 5. Reverse proxy (Pangolin or another trusted proxy)

The proxy's public HTTPS origin and its internal TLS target are separate identities. A backend certificate does not need the public hostname when
the proxy connects using a different, certificate-valid internal IP/name.

Example: public `https://lens.example.com`, upstream `https://192.168.10.20:18795`, verified connector peer `192.168.10.30`:

```powershell
& .\AuthLens.Api.exe --data-dir C:\AuthLens-Acceptance\server\data --network --listen 192.168.10.20 --port 18795 `
  --allowed-hosts 192.168.10.20 --proxy-hosts lens.example.com --trusted-proxies 192.168.10.30 `
  --cert C:\AuthLens-Acceptance\tls\server.pfx --cert-password-file C:\AuthLens-Acceptance\tls\cert-password
```

For managed Windows deployment set `AllowedHosts`, `ProxyHosts` and `TrustedProxies` in explicit deployment JSON. The test launcher supports
`AllowedHosts`/`TrustedProxies`; use the Server CLI or deployment module when proxy-only hosts are needed.

### Trust boundary

Confirm the TCP peer from network/refusal evidence before trusting it. With Newt it is usually the connector machine's LAN address, not the public
Pangolin host, DNS address or browser IP. No address is trusted implicitly, including loopback. CIDRs wider than IPv4 /24 or IPv6 /64 are refused;
prefer a single verified peer. Forwarded Host must be allowed, forwarded scheme must remain HTTPS and every walked hop must itself be trusted.
Client-supplied earlier hops are not trusted automatically. RFC `Forwarded` and Cloudflare-specific identity headers are not interpreted.

### Proxy resource checklist

| Setting | Requirement |
| --- | --- |
| Public domain | Intended AuthLens resource only |
| Upstream | Correct internal IP/name, HTTPS protocol and required port |
| Backend TLS | Verification enabled; upstream name matches SAN; trust configured in the component that opens the TLS connection |
| Host/forwarding | Preserve public Host or `X-Forwarded-Host`, `X-Forwarded-Proto: https` and the legitimate `X-Forwarded-For` chain |
| Authentication | Preserve existing proxy gate, access policies and AuthLens authentication |
| Exposure | Keep the backend behind the proxy; do not publish its management/listen port unnecessarily |

A proxy-gate 401 does not prove backend reachability. Authenticate through both gates and verify frontend assets, API requests, sessions and any
applicable WebSockets from outside the LAN. Do not weaken authentication to complete acceptance.

## 6. Firewall (one verified source, one port)

Inspect current service-scoped rules before changing them. Restrict new allowances to the verified connector and required direct-access clients/subnets,
TCP port and intended private/domain profiles. Do not add public/all-source rules or change unrelated resources. Confirm the connector can reach the
backend without disabling certificate validation. Opening a firewall port is not authentication.

## 7. Windows service and filesystem permissions

Use [supported Windows deployment](WINDOWS_DEPLOYMENT.md) with service `AuthLens`, identity `NT SERVICE\AuthLens`, explicit paths and verified
release packages. The service needs read access to program/TLS/keys and modify access only to its dedicated mutable storage. Keep root/configuration
restricted to administrators/SYSTEM and the intended operator. Never grant broad write access to fix a startup problem.

Audit before remediation. Preserve DACL backups, checksums and incomplete journals; a junction is accepted only at the explicitly configured release
pointer and only after target validation. See [NTFS permissions](WINDOWS_DEPLOYMENT.md#ntfs-permissions). Do not reset global Windows ACLs.

## 8. Acceptance

Verify normal chain/name TLS validation, readiness, correct build, account authorization, local same-origin login, rejection of foreign Origin,
missing CSRF and spoofed forwarding from an untrusted client. Restart the service and compare data/account/evidence fingerprints. Check external
access independently after proxy authentication. Use synthetic probes and focused tests, never credentials in logs or full regression by default.
